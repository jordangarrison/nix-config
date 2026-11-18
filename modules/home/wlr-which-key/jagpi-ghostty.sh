# A separate app-id keeps the Jagpi TUI distinct from ordinary terminals.
app_id="dev.jordangarrison.jagpi"
runtime_dir="${XDG_RUNTIME_DIR:?Run this launcher in a niri session}"

# Keep the lock until the new window is visible to niri, so rapid presses
# cannot create duplicates. The long-lived terminal must not inherit it.
exec 9>"$runtime_dir/jagpi-ghostty.lock"
flock -x 9

jagpi_window() {
  niri msg --json windows | jq -r --arg app_id "$app_id" \
    '[.[] | select(.app_id == $app_id)][0].id // empty'
}

window_id=$(jagpi_window)
if [[ -n "$window_id" ]]; then
  niri msg action focus-window --id "$window_id"
  exit 0
fi

# --class also separates Ghostty's D-Bus identity. Explicitly disable GTK
# handoff so a wedged primary instance cannot swallow the new window.
ghostty --class="$app_id" --gtk-single-instance=false --title=Jagpi -e "$@" \
  >"$runtime_dir/jagpi-ghostty.log" 2>&1 9>&- &
ghostty_pid=$!

for (( attempt=0; attempt<100; attempt++ )); do
  window_id=$(jagpi_window)
  if [[ -n "$window_id" ]]; then
    niri msg action focus-window --id "$window_id"
    exit 0
  fi
  if ! kill -0 "$ghostty_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

echo "Jagpi window did not become ready; see $runtime_dir/jagpi-ghostty.log" >&2
exit 1
