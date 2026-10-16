# shellcheck shell=bash
# The shell's own environment, and the one an application started from it
# gets. start-shell.sh runs quickshell with settings that are for the shell
# alone: two malloc arenas, Mesa's glthread and Gallium's threaded context
# off, the icon theme handed over in QS_ICON_THEME, and no KDE platform theme
# (see start-shell.sh for the measurements). Every process the shell starts
# inherits that environment - and an application should not: a browser, an
# editor or a remote-desktop client opened from the launcher ran with two
# arenas and without Mesa's threads, and Qt applications without the Plasma look
# (testing.md pitfall 80, the same mistake with a prctl).
#
# So start-shell.sh writes down what it changed:
#   BUCHHWIN_APP_ENV_UNSET  the settings it set that the session did not have
#   BUCHHWIN_APP_QPA_THEME  the session's QT_QPA_PLATFORMTHEME, which the shell
#                           runs without
# and app_env_restore undoes both in the calling script, right before it runs
# the application (scripts/launch-app.sh). A value the session had itself is
# not in the list and stays. Only the shell's own names are ever unset, so a
# stray list cannot take PATH or the display away from an application.
#
# A process from a shell older than that record has the settings without
# it - an editor opened from the launcher back then, and every deploy and
# link from it since. QS_ICON_THEME gives it away: nothing but
# start-shell.sh sets it. The session's own values are then the user
# manager's (session-init.sh imports them there): a setting the manager does
# not have is that shell's, and the platform theme comes back from there.
# Source this file.
app_env_shell_names=(MALLOC_ARENA_MAX mesa_glthread GALLIUM_THREAD QS_ICON_THEME)

app_env_restore() {
  local name known line session
  if [[ -n ${BUCHHWIN_APP_ENV_UNSET+set} || -n ${BUCHHWIN_APP_QPA_THEME+set} ]]; then
    for name in ${BUCHHWIN_APP_ENV_UNSET:-}; do
      for known in "${app_env_shell_names[@]}"; do
        if [[ $name == "$known" ]]; then unset "$name"; fi
      done
    done
    if [[ -n ${BUCHHWIN_APP_QPA_THEME:-} ]]; then
      export QT_QPA_PLATFORMTHEME=$BUCHHWIN_APP_QPA_THEME
    fi
    unset BUCHHWIN_APP_ENV_UNSET BUCHHWIN_APP_QPA_THEME
  elif [[ -n ${QS_ICON_THEME:-} ]]; then
    session=$(systemctl --user show-environment 2>/dev/null) || session=""
    for name in "${app_env_shell_names[@]}"; do
      [[ -n ${!name+set} ]] || continue
      if ! grep -qxF -- "$name=${!name}" <<<"$session"; then unset "$name"; fi
    done
    if [[ -z ${QT_QPA_PLATFORMTHEME:-} ]]; then
      while IFS= read -r line; do
        if [[ $line == QT_QPA_PLATFORMTHEME=?* ]]; then
          export QT_QPA_PLATFORMTHEME=${line#*=}
          break
        fi
      done <<<"$session"
    fi
  fi
  return 0
}
