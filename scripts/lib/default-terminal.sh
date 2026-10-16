# shellcheck shell=bash
# The session's terminal without starting Python: `default-apps.py get
# terminal` answers the same question in about 85 ms, on the path of every
# Super+Enter (16.10.: 340 ms from the key to the window, 88 of them that
# answer). Source this file; scripts/launch-default.sh does.
#
# The rule is default-apps.py's (terminal_default, InstalledApps):
#   - the first line of $XDG_CONFIG_HOME/buchhwin-shell-xdg-terminals.list
#     that names an installed entry, comments and blank lines skipped;
#   - else kitty.desktop when it is installed, else nothing;
#   - installed: the first data directory that has applications/<id> decides,
#     and its [Desktop Entry] must be an application (Type= missing or
#     Application) that is not Hidden=true - a hidden entry there hides a good
#     copy further down, as the XDG catalogue does.
# What this cannot answer for certain - an id with a dash and no file of that
# name, which may be a subdirectory - is left to default-apps.py: status 2.

# 0 installed, 1 not, 2 ask default-apps.py.
default_terminal_entry() {
  local id=$1 dir file line key value in_group any type hidden
  local -a dirs
  local -A seen
  [[ $id == *.desktop ]] || return 1
  IFS=: read -r -a dirs <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for dir in "${dirs[@]}"; do
    [[ -n $dir ]] || continue
    file=$dir/applications/$id
    [[ -f $file ]] || continue
    [[ -r $file ]] || return 1
    in_group=false any=false type=Application hidden=false
    seen=()
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line#"${line%%[![:space:]]*}"}
      line=${line%"${line##*[![:space:]]}"}
      if [[ $line == '['*']' ]]; then
        if [[ $line == '[Desktop Entry]' ]]; then in_group=true; else in_group=false; fi
      elif $in_group && [[ $line == *=* && $line != '#'* ]]; then
        key=${line%%=*}
        key=${key%"${key##*[![:space:]]}"}
        value=${line#*=}
        value=${value#"${value%%[![:space:]]*}"}
        # The first value of a key counts, as with setdefault.
        [[ -z ${seen["k$key"]+set} ]] || continue
        seen["k$key"]=1
        any=true
        case $key in
          Type) type=$value ;;
          Hidden) hidden=$value ;;
        esac
      fi
    done <"$file"
    if $any && [[ $type == Application && $hidden != true ]]; then return 0; fi
    return 1
  done
  [[ $id == *-* ]] && return 2
  return 1
}

# Prints the desktop id (empty: none), or returns 2 for default-apps.py.
default_terminal() {
  local list="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell-xdg-terminals.list" line state
  if [[ -f $list && -r $list ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line#"${line%%[![:space:]]*}"}
      line=${line%"${line##*[![:space:]]}"}
      [[ -n $line && $line != '#'* ]] || continue
      state=0; default_terminal_entry "$line" || state=$?
      case $state in
        0) printf '%s\n' "$line"; return 0 ;;
        2) return 2 ;;
      esac
    done <"$list"
  fi
  state=0; default_terminal_entry kitty.desktop || state=$?
  case $state in
    0) printf 'kitty.desktop\n' ;;
    1) printf '\n' ;;
    *) return 2 ;;
  esac
}
