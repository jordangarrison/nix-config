# Herdr's bare launch raises the window if it is already running (one per
# HERDR_APP_HOME). layout.switch needs a running window, so wait on startup.
app_home="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"
if [[ ! -f "$app_home/layouts/jagpi.json" ]]; then
  echo "Herdr Jagpi layout not found: $app_home/layouts/jagpi.json" >&2
  exit 1
fi

# Serialize shortcut presses, including the gap before a new window listens.
# Do not pass the lock to the long-lived app process.
exec 9>"$app_home/.jagpi-launch.lock"
flock -x 9
if ! timeout 2s herdr-app status >/dev/null 2>&1; then
  herdr-app >"$app_home/jagpi-launch.log" 2>&1 9>&- &
fi

deadline=$((SECONDS + 15))
until timeout 2s herdr-app status >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Herdr did not become ready; see $app_home/jagpi-launch.log" >&2
    exit 1
  fi
  sleep 0.1
done

# Fail rather than raise the wrong layout if Jagpi cannot be selected.
herdr-app 'do' layout.switch --name jagpi
herdr-app 9>&-
