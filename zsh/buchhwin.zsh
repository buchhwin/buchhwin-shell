# buchhwin-shell command wrappers, safe to source from any Zsh.
#
#   source ~/.config/buchhwin-shell/shell.zsh
#
# They make fastfetch, cmatrix and cava follow the shell accent (Settings >
# Terminal writes the files they read). An explicit flag on the command line
# always wins. Nothing here assumes the session's own ZDOTDIR.

buchhwin_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell"


# Use the session's copied Fastfetch configuration for manual calls too. The
# labels take the prompt colour from Settings > Terminal (fastfetch-color);
# flags after --config override the file's display.color.keys.
fastfetch() {
  local -a args
  local color=""
  if [[ -r "$buchhwin_config_dir/fastfetch.jsonc" ]]; then
    args=(--config "$buchhwin_config_dir/fastfetch.jsonc")
  fi
  [[ -r "$buchhwin_config_dir/fastfetch-color" ]] && color="$(<"$buchhwin_config_dir/fastfetch-color")"
  [[ "$color" =~ '^#[0-9a-fA-F]{6}$' ]] && args+=(--color-keys "$color")
  command fastfetch "${args[@]}" "$@"
}
alias ff=fastfetch

# cmatrix and cava follow the shell accent (Settings > Terminal writes both
# files). An explicit -C or -p on the command line always wins.
# cmatrix -C only knows eight colour names, and they are palette slots: the
# exact accent comes from repainting that slot for the run (OSC 4) and putting
# it back afterwards (OSC 104), which every terminal ignores safely.
cmatrix() {
  local color_file="$buchhwin_config_dir/cmatrix-color" name="" index="" hex=""
  [[ -r $color_file ]] && read -r name index hex < "$color_file"
  if [[ -z $name || "$*" == *-C* ]]; then
    command cmatrix "$@"
    return
  fi
  if [[ $index == <0-7> && $hex == (#i)\#[0-9a-f](#c6) ]]; then
    printf '\e]4;%s;%s\a' "$index" "$hex"
    {
      command cmatrix -C "$name" "$@"
    } always {
      printf '\e]104;%s\a' "$index"
    }
  else
    command cmatrix -C "$name" "$@"
  fi
}

cava() {
  local config="$buchhwin_config_dir/cava.conf"
  if [[ -r $config && "$*" != *-p* ]]; then
    command cava -p "$config" "$@"
  else
    command cava "$@"
  fi
}
