# Which distribution the installers are running on, and the package-manager
# commands that differ. Sourced, not run:
#
#   . "$project_dir/install/lib/distro.sh"
#   distro=$(distro_detect) || exit 2        # fedora | opensuse-leap | arch
#
# Supported are exactly the systems the package lists in install/packages/
# were checked against: Fedora, openSUSE Leap 16 and Arch Linux. Tumbleweed is
# refused on purpose - its Hyprland comes from somewhere else and was never
# tried. So are Arch's derivatives (ID_LIKE=arch): they share the package
# names but not always the repositories; BUCHHWIN_DISTRO=arch is the way in.
# BUCHHWIN_DISTRO overrides the detection (CI, tests, --list-packages for the
# other system); BUCHHWIN_OS_RELEASE points at another os-release (tests). The
# running shell has the same knowledge in services/distro/DistroLogic.js.

DISTROS=(fedora opensuse-leap arch)

# Prints the distribution, or explains on stderr and returns 1.
distro_detect() {
  if [[ -n ${BUCHHWIN_DISTRO:-} ]]; then
    distro_known "$BUCHHWIN_DISTRO" || {
      printf 'Unknown distribution %s (known: %s)\n' "$BUCHHWIN_DISTRO" "${DISTROS[*]}" >&2
      return 1
    }
    printf '%s\n' "$BUCHHWIN_DISTRO"
    return 0
  fi
  local file=${BUCHHWIN_OS_RELEASE:-/etc/os-release} ID="" VERSION_ID="" PRETTY_NAME=""
  if [[ ! -r $file ]]; then
    printf 'Cannot read %s, so the distribution is unknown.\n' "$file" >&2
    return 1
  fi
  # In a subshell: os-release is shell syntax, but it is not ours to let it
  # set anything else in the caller.
  IFS='|' read -r ID VERSION_ID PRETTY_NAME < <(
    # shellcheck disable=SC1090
    . "$file" 2>/dev/null
    printf '%s|%s|%s\n' "${ID:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-}")
  case $ID in
    fedora) printf 'fedora\n' ;;
    opensuse-leap)
      if [[ ${VERSION_ID%%.*} == 16 ]]; then
        printf 'opensuse-leap\n'
      else
        printf 'openSUSE Leap %s is not supported, only Leap 16.\n' "$VERSION_ID" >&2
        return 1
      fi ;;
    arch) printf 'arch\n' ;;
    *)
      printf '%s is not supported (Fedora, openSUSE Leap 16 and Arch Linux are).\n' "${PRETTY_NAME:-${ID:-This system}}" >&2
      printf 'Set BUCHHWIN_DISTRO to one of: %s, if you know what you are doing.\n' "${DISTROS[*]}" >&2
      return 1 ;;
  esac
}

distro_known() {
  local known
  for known in "${DISTROS[@]}"; do [[ $1 == "$known" ]] && return 0; done
  return 1
}

# The commands below print what they would run when the caller's `run` is a
# dry run; they never call the package manager themselves. `run` comes from
# the caller (install/bootstrap.sh).

# Set by a caller that wants every package and every dependency from one
# repository only (install/build-hyprland-leap.sh: repo-oss), so a third-party
# repository at the same priority cannot slip a newer library in underneath.
zypper_repo_args=()

# The alias of Leap's own repo-oss on this machine: it is "repo-oss" on one
# installation and "openSUSE:repo-oss" on the next, so it is read off the URL.
leap_oss_alias() {
  LC_ALL=C zypper --non-interactive --no-refresh lr -u 2>/dev/null \
    | awk -F'|' '$NF ~ /distribution\/leap\/16\.0\/repo\/oss\/?/ { gsub(/ /, "", $2); print $2; exit }' \
    || true   # no zypper (a Fedora CI running the dry run): no alias, not an error
}

# The alias of Packman when it is enabled, else nothing. Where it is, the
# multimedia libraries came from it (ffmpeg, on the machine this was written
# on), and a package that links them - wf-recorder - only resolves with it.
leap_packman_alias() {
  LC_ALL=C zypper --non-interactive --no-refresh lr -u -E 2>/dev/null \
    | awk -F'|' '$NF ~ /packman/ { gsub(/ /, "", $2); print $2; exit }' \
    || true
}

# pkg_install DISTRO PACKAGE...
pkg_install() {
  local distro=$1; shift
  case $distro in
    fedora) run sudo dnf -y install "$@" ;;
    # --no-recommends: what is installed is what the list says, nothing a
    # recommendation drags in on top of a running desktop.
    opensuse-leap) run sudo zypper --non-interactive install --no-recommends "${zypper_repo_args[@]}" "$@" ;;
    # --needed: what is installed already is left alone, so a second run
    # reinstalls nothing. No --noconfirm: pacman lists the transaction and
    # asks, and it asks again before it removes a conflicting package.
    arch) run sudo pacman -S --needed "$@" ;;
  esac
}

# pkg_install_preview DISTRO PACKAGE...: what the install would change,
# without changing it. zypper answers that in one command; on Fedora dnf
# prints its transaction and asks anyway. pacman's --print resolves the list
# against the local database without root, which catches a name the
# repositories do not have before sudo is asked for anything.
pkg_install_preview() {
  local distro=$1; shift
  case $distro in
    opensuse-leap) sudo env LC_ALL=C zypper --non-interactive install --no-recommends "${zypper_repo_args[@]}" --dry-run "$@" ;;
    arch) LC_ALL=C pacman -S --needed --print --print-format '%n %v' "$@" ;;
    *) return 0 ;;
  esac
}

# pkg_install_safe DISTRO PACKAGE...: pkg_install, but on openSUSE only after
# zypper's own dry run said it removes, downgrades and re-vendors nothing -
# this runs next to a working desktop. On Arch only after pacman resolved
# every name, downgrades nothing, and the system is not behind its own
# package database. Exits on refusal; nothing is installed. Needs the
# caller's `apply` (true/false) besides `run`.
pkg_install_safe() {
  local distro=$1; shift
  if $apply && [[ $distro == arch ]]; then
    # Upgrades the local database already knows about: a new package built
    # against those newer libraries, installed beside the old ones, is the
    # partial upgrade Arch does not support. -Qu reads the database as it is
    # (no -Sy here, ever); held-back packages (IgnorePkg) say "[ignored]" and
    # stay held. Captured, then searched (pitfall 15).
    local upgrades pending
    upgrades=$(LC_ALL=C pacman -Qu 2>/dev/null) || upgrades=""
    pending=$(grep -v -e '\[ignored\]$' -e '^$' <<<"$upgrades") || pending=""
    if [[ -n $pending ]]; then
      head -n 30 <<<"$pending" >&2
      printf '  The system is behind its package database (above). Nothing was installed.\n' >&2
      printf '  Run sudo pacman -Syu first, then this again.\n' >&2
      exit 1
    fi
    local preview
    preview=$(pkg_install_preview "$distro" "$@" 2>&1) || {
      printf '%s\n' "$preview" | tail -n 30 >&2
      printf '  pacman cannot resolve the list as it is (above). Nothing was installed.\n' >&2
      printf '  An old package database is the usual cause: sudo pacman -Syu first.\n' >&2
      exit 1
    }
    # --needed still installs a package the repositories have older than the
    # installed one (a build from the AUR or testing): pacman warns
    # "downgrading package X (new => old)" and goes ahead, as zypper's
    # DOWNGRADE would.
    if grep -q 'downgrading package' <<<"$preview"; then
      grep 'downgrading package' <<<"$preview" >&2
      printf '  That would downgrade installed packages. Nothing was installed.\n' >&2
      exit 1
    fi
  fi
  if $apply && [[ $distro == opensuse-leap ]]; then
    local preview
    preview=$(pkg_install_preview "$distro" "$@" 2>&1) || {
      printf '%s\n' "$preview" | tail -n 30 >&2
      printf '  zypper cannot install the list as it is (above). Nothing was installed.\n' >&2
      exit 1
    }
    if grep -qE 'going to be (REMOVED|DOWNGRADED)|change vendor|going to change vendor' <<<"$preview"; then
      printf '%s\n' "$preview" >&2
      printf '  That would remove, downgrade or switch the vendor of installed packages.\n' >&2
      printf '  Nothing was installed; the system is as it was.\n' >&2
      exit 1
    fi
  fi
  pkg_install "$distro" "$@"
}

# repo_add DISTRO SPEC: a Copr name on Fedora ("owner/project"), a
# "alias|url|priority" triple on openSUSE. Arch needs no repository of its
# own (everything is in extra, Brave comes from the AUR), so it has none.
repo_add() {
  local distro=$1 spec=$2
  case $distro in
    fedora) run sudo dnf -y copr enable "$spec" ;;
    opensuse-leap)
      local alias url priority
      IFS='|' read -r alias url priority <<<"$spec"
      if zypper --non-interactive lr "$alias" >/dev/null 2>&1; then
        printf '  %s: already configured\n' "$alias"
      elif [[ $url == *.repo ]]; then
        # A .repo file brings its own alias; it has to match the one above.
        run sudo zypper --non-interactive addrepo --refresh --priority "$priority" "$url"
      else
        run sudo zypper --non-interactive addrepo --refresh --priority "$priority" "$url" "$alias"
      fi ;;
  esac
}

# repos_refresh DISTRO: after repo_add. zypper asks once per new repository
# whether to trust its key; --gpg-auto-import-keys answers yes, which is why
# the dry run lists every repository first. Nothing on Arch on purpose: a
# refresh without an upgrade (pacman -Sy) is a partial upgrade waiting to
# happen; bootstrap.sh asks for sudo pacman -Syu before it instead.
repos_refresh() {
  case $1 in
    opensuse-leap) run sudo zypper --non-interactive --gpg-auto-import-keys refresh ;;
  esac
}

# distro_install_hint DISTRO PACKAGE: the command a check prints next to a
# missing package, or a note that the distribution does not package it.
distro_install_hint() {
  local distro=$1 package=$2
  case $distro:$package in
    opensuse-leap:hyprland-guiutils) printf 'built with Hyprland: install/build-hyprland-leap.sh --apply' ;;
    opensuse-leap:cmatrix) printf 'not packaged for openSUSE Leap' ;;
    opensuse-leap:*) printf 'sudo zypper install %s' "$package" ;;
    arch:brave-bin) printf 'paru -S brave-bin (from the AUR)' ;;
    arch:*) printf 'sudo pacman -S %s' "$package" ;;
    *) printf 'sudo dnf install %s' "$package" ;;
  esac
}
