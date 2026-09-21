# Dedicated Zsh configuration for the buchhwin-shell session.
# Kitty loads it through ZDOTDIR; the account's personal dotfiles are not read.
export PATH="$HOME/.local/bin:$PATH"

buchhwin_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell"
buchhwin_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/buchhwin-shell"
buchhwin_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/buchhwin-shell"

# The prompt from Settings > Terminal, or the repository default.
if [[ -r "$buchhwin_config_dir/starship.toml" ]]; then
  export STARSHIP_CONFIG="$buchhwin_config_dir/starship.toml"
else
  export STARSHIP_CONFIG="${ZDOTDIR:-${0:A:h}}/starship.toml"
fi
# The command wrappers live in a fragment so a personal .zshrc can source
# the same file (install/install.sh links it into the config directory).
source "${ZDOTDIR:-${0:A:h}}/buchhwin.zsh"

if [[ -o interactive ]]; then
  # Test before forking: `mkdir -p` on a directory that is already there does
  # nothing, but it still costs a process, and this file runs once per window,
  # tab, pane and nested shell.
  [[ -d $buchhwin_state_dir && -d $buchhwin_cache_dir ]] \
    || mkdir -p -- "$buchhwin_state_dir" "$buchhwin_cache_dir"
  HISTFILE="$buchhwin_state_dir/zsh_history"
  HISTSIZE=10000
  SAVEHIST=10000
  setopt APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

  # Completion, without re-stating the whole $fpath on every shell start.
  # `compinit` did that every time - 28 ms of the 81 the rc file cost - to
  # rebuild a dump that changes when packages are installed, not between two
  # terminals. So: rebuild it once a day and trust it the rest of the time
  # (`-C`), and keep a compiled copy beside it, because a 53 KB dump that is
  # read as plain text is read as plain text every single time.
  #
  # `(N.mh+24)` is a glob qualifier: N so no match is not an error, . for a
  # plain file, mh+24 for "last modified more than 24 hours ago". A match
  # therefore means the dump is stale.
  #
  # It has to be assigned to an array. `[[ -n $file(#qN.mh+24) ]]` looks like
  # it asks the same question and does not: `[[ ]]` performs no filename
  # generation, so the qualifier stays literal text and `-n` is true whatever
  # the file's age - which would have left this running the full compinit
  # every time while looking fixed. Checked both ways round against a file
  # made three days old.
  autoload -Uz compinit
  buchhwin_zcompdump="$buchhwin_cache_dir/zcompdump"
  buchhwin_stale=( ${buchhwin_zcompdump}(N.mh+24) )
  if (( $#buchhwin_stale )) || [[ ! -s $buchhwin_zcompdump ]]; then
    compinit -d "$buchhwin_zcompdump"
    # Compile in the background: the win is for the *next* shell, and this one
    # should not wait for it.
    { zcompile -R -- "$buchhwin_zcompdump" } &!
  else
    compinit -C -d "$buchhwin_zcompdump"
  fi
  unset buchhwin_zcompdump buchhwin_stale
  zstyle ':completion:*' menu select
  zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
  bindkey '^I' expand-or-complete

  # Settings > Terminal writes 0 into this file to disable the greeting.
  fastfetch_start_file="$buchhwin_config_dir/fastfetch-on-start"
  if [[ ! -r "$fastfetch_start_file" || "$(<$fastfetch_start_file)" != "0" ]]; then
    (( $+commands[fastfetch] )) && fastfetch
  fi
  (( $+commands[starship] )) && eval "$(starship init zsh)"

  [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] \
    && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  # Load highlighting last so it can wrap all previously registered widgets.
  [[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
    && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
