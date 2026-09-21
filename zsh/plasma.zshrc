# Zsh for Plasma terminals, installed as ~/.zshrc by install/plasma-terminal.sh.
# Mirrors the buchhwin session profile: Fastfetch greeting, Starship prompt,
# autosuggestions and syntax highlighting.
export PATH="$HOME/.local/bin:$PATH"
export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"

alias ff=fastfetch

if [[ -o interactive ]]; then
  zsh_state="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
  zsh_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  mkdir -p -- "$zsh_state" "$zsh_cache"
  HISTFILE="$zsh_state/history"
  HISTSIZE=10000
  SAVEHIST=10000
  setopt APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

  autoload -Uz compinit
  compinit -d "$zsh_cache/zcompdump"
  zstyle ':completion:*' menu select
  zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
  bindkey '^I' expand-or-complete
  bindkey '^[[H' beginning-of-line
  bindkey '^[[F' end-of-line
  bindkey '^[[3~' delete-char

  # Writing 0 into this file disables the greeting in new terminals.
  fastfetch_start_file="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/on-start"
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
