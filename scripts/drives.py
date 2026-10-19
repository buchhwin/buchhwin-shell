#!/usr/bin/env python3
"""Removable drives and MTP phones for buchhwin-shell.

Only reads: mounting, unmounting, unlocking, locking and powering off go
through `udisksctl` and `gio mount` from the shell. Block devices come from
UDisks2 on the system bus, MTP phones from the gvfs volume monitor (GIO),
which UDisks2 does not see. `list` prints one JSON object on one line:

  {"kind": "drives", "mtp": BOOL,
   "drives": [{"id", "name", "bus", "size", "canPowerOff", "ejectable",
     "volumes": [{"id", "device", "label", "fsType", "size", "mountPoints",
       "readOnly", and for LUKS: "encrypted", "unlocked", "clearDevice"}]}],
   "phones": [{"id", "name", "uri", "mountPoint", "mounted"}]}

or, when UDisks2 cannot be read, {"kind": "error", "message": "..."} and
exit status 1.
Internal disks, loop devices, swap, optical media, system partitions and
devices without a filesystem are left out; encrypted (LUKS) volumes stay in
the list while they are locked. "mtp" is false when gvfs-mtp is missing, so
the shell can say so instead of listing nothing.

The shell runs `list` whenever `udisksctl monitor` or `gio mount -o` prints a
line, and works out what came and went itself (DrivesLogic.settle). A
`monitor` command used to stay resident for that, with PyGObject and
dbus-python - some 20 MB for events that come a few times a week.

  drives.py list
"""

import argparse
import json
import os
import re
import sys

UDISKS = "org.freedesktop.UDisks2"
UDISKS_PATH = "/org/freedesktop/UDisks2"
BLOCK = UDISKS + ".Block"
FILESYSTEM = UDISKS + ".Filesystem"
DRIVE = UDISKS + ".Drive"
LOOP = UDISKS + ".Loop"
SWAP = UDISKS + ".Swapspace"
ENCRYPTED = UDISKS + ".Encrypted"

HOTPLUG_BUSES = {"usb", "sdio", "ieee1394"}
# Never offered even if a hint is wrong (e.g. a system on an external disk).
SYSTEM_MOUNTS = {"/", "/boot", "/boot/efi", "/efi", "/home", "/usr", "/var", "/sysroot", "/etc", "/opt", "/srv"}
# gvfs' MTP backend; without it phones cannot be listed or mounted at all.
# Arch builds with libexecdir=/usr/lib, so its backend sits there directly.
MTP_BACKENDS = ("/usr/libexec/gvfsd-mtp", "/usr/libexec/gvfs/gvfsd-mtp", "/usr/lib/gvfs/gvfsd-mtp",
                "/usr/lib64/gvfs/gvfsd-mtp", "/usr/lib/gvfs/1.0/gvfsd-mtp", "/usr/lib/gvfsd-mtp")


def emit(**values):
    try:
        sys.stdout.write(json.dumps(values, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        sys.exit(0)


# ---- pure conversion (unit tested with synthetic property dicts) ------------

def text(value):
    """UDisks byte arrays (ay) are NUL-terminated paths; strings pass through."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    data = bytes(int(item) for item in value)
    return data.split(b"\0", 1)[0].decode("utf-8", "replace")


def base_name(path):
    return str(path).rstrip("/").rsplit("/", 1)[-1]


def removable_drive(drive):
    """True for USB sticks, SD cards and external disks; false for internal and optical drives."""
    if not drive:
        return False
    if drive.get("Optical") or any(str(item).startswith("optical") for item in drive.get("MediaCompatibility", [])):
        return False
    return bool(drive.get("Removable") or drive.get("MediaRemovable") or drive.get("Ejectable")
                or str(drive.get("ConnectionBus", "")) in HOTPLUG_BUSES)


def volume_from(interfaces):
    """A mountable volume dict for one block object, or None."""
    block = interfaces.get(BLOCK)
    filesystem = interfaces.get(FILESYSTEM)
    if block is None or filesystem is None or LOOP in interfaces or SWAP in interfaces:
        return None
    if block.get("HintIgnore") or block.get("HintSystem"):
        return None
    if str(block.get("IdUsage", "")) != "filesystem" or str(block.get("Drive", "/")) == "/":
        return None
    mounts = [text(item) for item in filesystem.get("MountPoints", [])]
    mounts = [item for item in mounts if item]
    if any(item in SYSTEM_MOUNTS for item in mounts):
        return None
    device = text(block.get("PreferredDevice")) or text(block.get("Device"))
    if not device.startswith("/dev/"):
        return None
    return {
        "device": device,
        "label": str(block.get("IdLabel", "")),
        "fsType": str(block.get("IdType", "")),
        "size": int(block.get("Size", 0)),
        "mountPoints": mounts,
        "readOnly": bool(block.get("ReadOnly", False)),
    }


def encrypted_volume_from(interfaces):
    """A LUKS block as a volume dict (still locked), or None.

    UDisks keeps the encrypted block and its unlocked cleartext device as two
    objects; the cleartext half is merged in by build_drives.
    """
    block = interfaces.get(BLOCK)
    if block is None or ENCRYPTED not in interfaces or LOOP in interfaces or SWAP in interfaces:
        return None
    if block.get("HintIgnore") or block.get("HintSystem"):
        return None
    if str(block.get("Drive", "/")) == "/":
        return None
    device = text(block.get("PreferredDevice")) or text(block.get("Device"))
    if not device.startswith("/dev/"):
        return None
    return {
        "device": device,
        "label": str(block.get("IdLabel", "")),
        "fsType": str(block.get("IdType", "")),
        "size": int(block.get("Size", 0)),
        "mountPoints": [],
        "readOnly": bool(block.get("ReadOnly", False)),
        "encrypted": True,
        "unlocked": False,
        "clearDevice": "",
    }


def cleartext_info(interfaces):
    """Filesystem data of an unlocked cleartext device (`CryptoBackingDevice` set)."""
    block = interfaces.get(BLOCK)
    if block is None:
        return None
    device = text(block.get("PreferredDevice")) or text(block.get("Device"))
    if not device.startswith("/dev/"):
        return None
    filesystem = interfaces.get(FILESYSTEM) or {}
    mounts = [item for item in (text(item) for item in filesystem.get("MountPoints", [])) if item]
    return {
        "clearDevice": device,
        "label": str(block.get("IdLabel", "")),
        "fsType": str(block.get("IdType", "")),
        "mountPoints": mounts,
        "readOnly": bool(block.get("ReadOnly", False)),
    }


def backing_path(interfaces):
    """Object path of the LUKS device this block is the cleartext of, or ""."""
    block = interfaces.get(BLOCK)
    if block is None:
        return ""
    path = str(block.get("CryptoBackingDevice", "/"))
    return "" if path == "/" else path


def drive_name(drive):
    parts = [str(drive.get("Vendor", "")).strip(), str(drive.get("Model", "")).strip()]
    return " ".join(part for part in parts if part)


def build_drives(objects):
    """GetManagedObjects-shaped dict (path -> interface -> properties) to sorted drives."""
    cleartext = {}
    for interfaces in objects.values():
        backing = backing_path(interfaces)
        info = cleartext_info(interfaces) if backing else None
        if info is not None:
            cleartext[backing] = info
    drives = {}
    for path, interfaces in objects.items():
        # The cleartext device is shown as part of its encrypted volume.
        if backing_path(interfaces):
            continue
        volume = encrypted_volume_from(interfaces)
        if volume is not None:
            unlocked = cleartext.get(path)
            if unlocked is not None:
                volume["unlocked"] = True
                volume["clearDevice"] = unlocked["clearDevice"]
                volume["mountPoints"] = unlocked["mountPoints"]
                volume["readOnly"] = volume["readOnly"] or unlocked["readOnly"]
                if unlocked["fsType"]:
                    volume["fsType"] = unlocked["fsType"]
                if unlocked["label"]:
                    volume["label"] = unlocked["label"]
        else:
            volume = volume_from(interfaces)
        if volume is None:
            continue
        if any(item in SYSTEM_MOUNTS for item in volume["mountPoints"]):
            continue
        drive_path = str(interfaces[BLOCK].get("Drive"))
        drive = objects.get(drive_path, {}).get(DRIVE)
        if not removable_drive(drive):
            continue
        entry = drives.get(drive_path)
        if entry is None:
            entry = drives[drive_path] = {
                "id": base_name(drive_path),
                "name": drive_name(drive),
                "bus": str(drive.get("ConnectionBus", "")),
                "size": int(drive.get("Size", 0)),
                "canPowerOff": bool(drive.get("CanPowerOff", False)),
                "ejectable": bool(drive.get("Ejectable", False)),
                "volumes": [],
            }
        volume["id"] = base_name(path)
        entry["volumes"].append(volume)
    result = sorted(drives.values(), key=lambda item: item["id"])
    for entry in result:
        entry["volumes"].sort(key=lambda item: item["device"])
        if entry["size"] <= 0:
            entry["size"] = sum(item["size"] for item in entry["volumes"])
    return result


# ---- MTP phones (gvfs, not visible to UDisks2) -------------------------------

def mtp_available():
    """True when the gvfs MTP backend is installed."""
    return any(os.path.exists(path) for path in MTP_BACKENDS)


def mtp_id(uri):
    """Stable id from an MTP URI, safe for IPC and object keys."""
    return "mtp-" + re.sub(r"[^A-Za-z0-9]+", "_", str(uri)[len("mtp://"):]).strip("_").lower()


def same_device(first, second):
    """Two MTP URIs address the same phone (gvfs adds or drops the trailing slash)."""
    return bool(first) and bool(second) and first.rstrip("/") == second.rstrip("/")


def phone_entry(name, uri, mount):
    return {
        "id": mtp_id(uri),
        "name": str(name or "").strip() or "Phone",
        "uri": uri,
        "mountPoint": str((mount or {}).get("path", "") or ""),
        "mounted": mount is not None,
    }


def build_phones(volumes, mounts):
    """GIO volumes and mounts (plain dicts) to sorted phone entries."""
    phones = {}
    taken = set()
    for volume in volumes or []:
        uri = str(volume.get("uri", "") or "")
        if not uri.startswith("mtp://"):
            continue
        match = None
        for index, mount in enumerate(mounts or []):
            if index in taken or not same_device(uri, str(mount.get("uri", "") or "")):
                continue
            match = mount
            taken.add(index)
            break
        entry = phone_entry(volume.get("name"), uri, match)
        phones.setdefault(entry["id"], entry)
    # A phone mounted without a volume (gvfs lost the device) is still usable.
    for index, mount in enumerate(mounts or []):
        uri = str(mount.get("uri", "") or "")
        if index in taken or not uri.startswith("mtp://"):
            continue
        entry = phone_entry(mount.get("name"), uri, mount)
        phones.setdefault(entry["id"], entry)
    return sorted(phones.values(), key=lambda item: (item["name"].lower(), item["id"]))


def volume_monitor():
    """The GIO volume monitor, or None when gvfs is unavailable."""
    try:
        import gi  # noqa: PLC0415 - only needed with a session bus
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio  # noqa: PLC0415
        return Gio.VolumeMonitor.get()
    except Exception:  # noqa: BLE001 - no session bus or no gvfs
        return None


def read_gio(monitor):
    """Volumes and mounts of the GIO monitor as plain dicts."""
    volumes = []
    for volume in monitor.get_volumes():
        root = volume.get_activation_root()
        volumes.append({"name": volume.get_name() or "", "uri": root.get_uri() if root else ""})
    mounts = []
    for mount in monitor.get_mounts():
        root = mount.get_root()
        mounts.append({"name": mount.get_name() or "", "uri": root.get_uri() if root else "",
                       "path": (root.get_path() if root else "") or ""})
    return volumes, mounts


def read_phones(monitor):
    if monitor is None or not mtp_available():
        return []
    try:
        return build_phones(*read_gio(monitor))
    except Exception:  # noqa: BLE001 - gvfs restarting
        return []


# ---- D-Bus ------------------------------------------------------------------

def plain(value):
    """dbus-python values to plain Python types."""
    import dbus  # noqa: PLC0415 - only needed with a bus
    if isinstance(value, dbus.Boolean):
        return bool(value)
    if isinstance(value, (dbus.Byte, dbus.Int16, dbus.Int32, dbus.Int64, dbus.UInt16, dbus.UInt32, dbus.UInt64)):
        return int(value)
    if isinstance(value, (dbus.String, dbus.ObjectPath, dbus.Signature)):
        return str(value)
    if isinstance(value, dbus.Dictionary):
        return {str(key): plain(item) for key, item in value.items()}
    if isinstance(value, (dbus.Array, dbus.Struct, list, tuple)):
        return [plain(item) for item in value]
    return value


def read_objects(bus):
    import dbus  # noqa: PLC0415
    manager = dbus.Interface(bus.get_object(UDISKS, UDISKS_PATH), "org.freedesktop.DBus.ObjectManager")
    return plain(manager.GetManagedObjects())


def snapshot(bus, monitor=None):
    """Drives plus MTP phones, or (None, message) when UDisks2 cannot be read."""
    try:
        drives = build_drives(read_objects(bus))
    except Exception as error:  # noqa: BLE001 - udisksd missing or restarting
        return None, str(error).splitlines()[0] if str(error) else "UDisks2 is not available"
    return {"drives": drives, "phones": read_phones(monitor)}, None


def emit_state(state):
    emit(kind="drives", drives=state["drives"], phones=state["phones"], mtp=mtp_available())


def command_list():
    import dbus  # noqa: PLC0415
    state, error = snapshot(dbus.SystemBus(), volume_monitor())
    if error:
        emit(kind="error", message=error)
        return 1
    emit_state(state)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["list"])
    parser.parse_args(argv)
    return command_list()


if __name__ == "__main__":
    sys.exit(main())
