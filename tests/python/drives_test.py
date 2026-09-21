#!/usr/bin/env python3
"""Unit test for scripts/drives.py filtering with synthetic UDisks2 objects (no bus)."""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("drives", ROOT / "scripts" / "drives.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def path_bytes(value):
    """UDisks sends paths as NUL-terminated byte arrays."""
    return list(value.encode()) + [0]


PREFIX = "/org/freedesktop/UDisks2/"


def drive(name, **props):
    values = {"Vendor": "", "Model": "", "Removable": False, "MediaRemovable": False, "Ejectable": False,
              "ConnectionBus": "", "CanPowerOff": False, "Optical": False, "MediaCompatibility": [], "Size": 0}
    values.update(props)
    return PREFIX + "drives/" + name, {module.DRIVE: values}


def block(name, drive_name, usage="filesystem", fs="vfat", label="", size=1000, mounts=(), system=False,
          ignore=False, extra=None, filesystem=True, encrypted=False, backing=None, read_only=False):
    interfaces = {module.BLOCK: {"Device": path_bytes("/dev/" + name), "PreferredDevice": path_bytes("/dev/" + name),
                                 "Drive": PREFIX + "drives/" + drive_name if drive_name else "/", "IdUsage": usage,
                                 "IdType": fs, "IdLabel": label, "Size": size, "HintSystem": system,
                                 "HintIgnore": ignore, "ReadOnly": read_only,
                                 "CryptoBackingDevice": PREFIX + "block_devices/" + backing if backing else "/"}}
    if filesystem:
        interfaces[module.FILESYSTEM] = {"MountPoints": [path_bytes(item) for item in mounts]}
    if encrypted:
        interfaces[module.ENCRYPTED] = {"HintEncryptionType": "luks2"}
    for key in extra or []:
        interfaces[key] = {}
    return PREFIX + "block_devices/" + name, interfaces


objects = dict([
    # Internal NVMe disk: system hint, not removable.
    drive("Internal_SSD", Model="Internal SSD", Size=512000000000),
    block("nvme0n1p5", "Internal_SSD", fs="ext4", mounts=["/boot"], system=True),
    block("nvme0n1p6", "Internal_SSD", fs="btrfs", mounts=["/", "/home"], system=True),
    # USB stick with a partition table and one FAT partition, not mounted.
    drive("SanDisk_Ultra_1", Vendor="SanDisk", Model="Ultra", Removable=True, ConnectionBus="usb",
          CanPowerOff=True, Size=16000000000),
    block("sdb", "SanDisk_Ultra_1", usage="", fs="", size=16000000000, filesystem=False, extra=[PREFIX + "PartitionTable"]),
    block("sdb1", "SanDisk_Ultra_1", fs="vfat", label="STICK", size=15990000000),
    # SD card without a partition table (superfloppy), mounted; the reader cannot power off.
    drive("SD_Reader", Model="SD/MMC", MediaRemovable=True, ConnectionBus="sdio", Size=0),
    block("mmcblk0", "SD_Reader", fs="exfat", label="CAMERA", size=64000000000, mounts=["/run/media/user/CAMERA"]),
    # External disk with two partitions (ordering by device) plus swap and LUKS.
    drive("WD_Elements", Vendor="WD", Model="Elements", Removable=True, ConnectionBus="usb", CanPowerOff=True,
          Size=2000000000000),
    block("sdc2", "WD_Elements", fs="ext4", label="Backup", mounts=["/run/media/user/Backup"]),
    block("sdc1", "WD_Elements", fs="ntfs", label="Data"),
    block("sdc3", "WD_Elements", usage="other", fs="swap", filesystem=False, extra=[module.SWAP]),
    # Locked LUKS partition: listed so the shell can offer "Unlock…".
    block("sdc4", "WD_Elements", usage="crypto", fs="crypto_LUKS", label="VAULT", size=500000000000,
          filesystem=False, encrypted=True),
    # Unlocked LUKS partition plus its mounted cleartext device (dm-0).
    block("sdc5", "WD_Elements", usage="crypto", fs="crypto_LUKS", label="", size=250000000000,
          filesystem=False, encrypted=True),
    block("dm-0", "WD_Elements", fs="ext4", label="Archive", size=250000000000,
          mounts=["/run/media/user/Archive"], backing="sdc5"),
    # An unlocked system volume on a removable disk stays out through its mount.
    block("sdc6", "WD_Elements", usage="crypto", fs="crypto_LUKS", filesystem=False, encrypted=True),
    block("dm-1", "WD_Elements", fs="ext4", mounts=["/home"], backing="sdc6"),
    # Loop device with a filesystem (no drive).
    block("loop0", None, fs="squashfs", mounts=["/var/lib/snapd/snap/core"], extra=[module.LOOP]),
    # Optical drive with a data disc.
    drive("DVD", Model="DVD-RW", Removable=True, MediaRemovable=True, Ejectable=True, Optical=True,
          MediaCompatibility=["optical_cd", "optical_dvd"]),
    block("sr0", "DVD", fs="iso9660", label="DISC"),
    # USB disk hidden by a udev rule, and one carrying a system mount.
    drive("Hidden_USB", Removable=True, ConnectionBus="usb"),
    block("sdd1", "Hidden_USB", ignore=True),
    drive("Root_USB", Removable=True, ConnectionBus="usb"),
    block("sde1", "Root_USB", fs="ext4", mounts=["/"]),
    # Internal SATA disk without the system hint (secondary disk) stays out.
    drive("Second_HDD", Model="HDD", ConnectionBus="", Size=1000),
    block("sda1", "Second_HDD", fs="ext4"),
    # Block that points at a drive object that does not exist (vanished).
    block("sdf1", "Gone"),
])

drives = module.build_drives(objects)
check([item["id"] for item in drives] == ["SD_Reader", "SanDisk_Ultra_1", "WD_Elements"],
      "only removable drives: %r" % [item["id"] for item in drives])
by_id = {item["id"]: item for item in drives}

stick = by_id["SanDisk_Ultra_1"]
check(stick["name"] == "SanDisk Ultra", "vendor and model: %r" % stick["name"])
check(stick["bus"] == "usb" and stick["canPowerOff"] and stick["size"] == 16000000000, "stick properties")
check([volume["id"] for volume in stick["volumes"]] == ["sdb1"], "partition table block is skipped")
check(stick["volumes"][0] == {"device": "/dev/sdb1", "label": "STICK", "fsType": "vfat", "size": 15990000000,
                               "mountPoints": [], "readOnly": False, "id": "sdb1"}, "volume dict: %r" % stick["volumes"][0])

card = by_id["SD_Reader"]
check(card["volumes"][0]["mountPoints"] == ["/run/media/user/CAMERA"], "byte array mount point decoded")
check(card["size"] == 64000000000, "drive size falls back to the volumes")
check(not card["canPowerOff"], "card reader cannot power off")

disk = by_id["WD_Elements"]
check([volume["device"] for volume in disk["volumes"]] == ["/dev/sdc1", "/dev/sdc2", "/dev/sdc4", "/dev/sdc5"],
      "swap and cleartext devices skipped, sorted: %r" % [volume["device"] for volume in disk["volumes"]])
by_device = {volume["device"]: volume for volume in disk["volumes"]}
check(by_device["/dev/sdc4"] == {"device": "/dev/sdc4", "label": "VAULT", "fsType": "crypto_LUKS",
                                 "size": 500000000000, "mountPoints": [], "readOnly": False, "encrypted": True,
                                 "unlocked": False, "clearDevice": "", "id": "sdc4"},
      "locked LUKS volume: %r" % by_device["/dev/sdc4"])
check(by_device["/dev/sdc5"] == {"device": "/dev/sdc5", "label": "Archive", "fsType": "ext4",
                                 "size": 250000000000, "mountPoints": ["/run/media/user/Archive"], "readOnly": False,
                                 "encrypted": True, "unlocked": True, "clearDevice": "/dev/dm-0", "id": "sdc5"},
      "unlocked LUKS volume carries the cleartext device: %r" % by_device["/dev/sdc5"])
check(not any(volume["device"].startswith("/dev/dm-") for volume in disk["volumes"]), "cleartext device is not its own volume")
check("encrypted" not in by_device["/dev/sdc1"], "plain volumes stay unchanged")
check(module.encrypted_volume_from({module.BLOCK: {"Drive": "/", "Device": path_bytes("/dev/sdx1")},
                                    module.ENCRYPTED: {}}) is None, "encrypted block without a drive rejected")
check(module.backing_path({module.BLOCK: {"CryptoBackingDevice": "/"}}) == "", "no backing device")
check(module.backing_path({}) == "", "no block interface")

check(module.text(None) == "" and module.text("x") == "x" and module.text([47, 0, 65]) == "/", "text conversion")
check(module.removable_drive({"ConnectionBus": "sdio"}), "sdio bus counts as removable")
check(not module.removable_drive({}), "empty drive")
check(not module.removable_drive(None), "no drive")
check(module.volume_from({module.BLOCK: {"Drive": PREFIX + "drives/x", "IdUsage": "filesystem", "Device": "sdb1"},
                          module.FILESYSTEM: {}}) is None, "device outside /dev rejected")

# Events between snapshots.
before = module.build_drives(objects)
after_objects = dict(objects)
del after_objects[PREFIX + "drives/SD_Reader"]
after_objects.update([block("sdb1", "SanDisk_Ultra_1", fs="vfat", label="STICK", mounts=["/run/media/user/STICK"]),
                      block("sdc2", "WD_Elements", fs="ext4", label="Backup"),
                      drive("Kingston_1", Model="DataTraveler", Removable=True, ConnectionBus="usb"),
                      block("sdg1", "Kingston_1", fs="exfat")])
events = module.diff(before, module.build_drives(after_objects))
check(events == [{"kind": "added", "id": "Kingston_1"},
                 {"kind": "removed", "id": "SD_Reader"},
                 {"kind": "mounted", "id": "sdb1", "drive": "SanDisk_Ultra_1"},
                 {"kind": "unmounted", "id": "sdc2", "drive": "WD_Elements"}], "events: %r" % events)
check(module.diff(before, before) == [], "no events without changes")
check(module.diff([], []) == [], "empty lists")

# Unlocking a volume between two snapshots is a mount event for the shell.
unlocked_objects = dict(objects)
del unlocked_objects[PREFIX + "block_devices/dm-0"]
events = module.diff(module.build_drives(unlocked_objects), before)
check(events == [{"kind": "mounted", "id": "sdc5", "drive": "WD_Elements"}], "unlock shows up as mounted: %r" % events)

# MTP phones from the gvfs volume monitor (UDisks2 never sees them).
volumes = [{"name": "Windows", "uri": "file:///run/media/user/Windows"},
           {"name": "Pixel 7", "uri": "mtp://Google_Pixel_7_1A2B/"},
           {"name": "", "uri": "mtp://%5Busb%3A001%2C005%5D/"},
           {"name": "Broken", "uri": ""}]
mounts = [{"name": "Pixel 7", "uri": "mtp://Google_Pixel_7_1A2B", "path": "/run/user/1000/gvfs/mtp:host=Google_Pixel_7_1A2B"},
          {"name": "Backup", "uri": "file:///run/media/user/Backup", "path": "/run/media/user/Backup"},
          {"name": "Old phone", "uri": "mtp://Nokia_9/", "path": "/run/user/1000/gvfs/mtp:host=Nokia_9"}]
phones = module.build_phones(volumes, mounts)
check([item["id"] for item in phones] == ["mtp-nokia_9", "mtp-5busb_3a001_2c005_5d", "mtp-google_pixel_7_1a2b"],
      "phones sorted by name, non-MTP left out: %r" % [item["id"] for item in phones])
by_name = {item["name"]: item for item in phones}
check(by_name["Pixel 7"] == {"id": "mtp-google_pixel_7_1a2b", "name": "Pixel 7", "uri": "mtp://Google_Pixel_7_1A2B/",
                             "mountPoint": "/run/user/1000/gvfs/mtp:host=Google_Pixel_7_1A2B", "mounted": True},
      "mount matched to the volume despite the trailing slash: %r" % by_name["Pixel 7"])
check(by_name["Phone"]["mounted"] is False and by_name["Phone"]["mountPoint"] == "", "unmounted phone without a name")
check(by_name["Old phone"]["mounted"] is True, "a mount without a volume is still listed")
check(module.build_phones([], []) == [] and module.build_phones(None, None) == [], "no phones")
check(module.mtp_id("mtp://[usb:001,005]/") == "mtp-usb_001_005", "id from a legacy URI")
check(module.same_device("mtp://X/", "mtp://X") and not module.same_device("mtp://X/", "mtp://Y/"), "URI comparison")
check(module.same_device("", "") is False, "empty URIs never match")

events = module.diff_phones(phones, [dict(by_name["Pixel 7"], mounted=False, mountPoint=""),
                                     {"id": "mtp-new", "name": "New", "uri": "mtp://New/", "mountPoint": "", "mounted": False}])
check(events == [{"kind": "phoneAdded", "id": "mtp-new"},
                 {"kind": "phoneRemoved", "id": "mtp-nokia_9"},
                 {"kind": "phoneRemoved", "id": "mtp-5busb_3a001_2c005_5d"},
                 {"kind": "phoneUnmounted", "id": "mtp-google_pixel_7_1a2b"}], "phone events: %r" % events)
check(module.diff_phones(phones, phones) == [], "no phone events without changes")
check(isinstance(module.mtp_available(), bool), "gvfs-mtp presence is a plain flag")

if failures:
    for failure in failures:
        print("FAIL", failure)
    print("TESTS FAILED drives_test")
    sys.exit(1)
print("TESTS PASSED drives_test")
