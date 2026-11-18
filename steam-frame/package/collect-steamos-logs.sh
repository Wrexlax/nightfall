#!/bin/bash
# Copies SteamOS's own logs (Steam, gamescope, PipeWire/WirePlumber, SteamVR)
# into ~/Downloads/Nightfall-logs/steamos-<time>/ so they can be uploaded.
# Read-only: it changes nothing. Double-click to run (or run it in Konsole).
# Best run right after the problem happens, before restarting the headset.
# The copies go through share_log.py, which masks network addresses, ids and
# names. These are other programs' logs, though, and long: look through them
# before posting them anywhere public.
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

OUT="$HOME/Downloads/Nightfall-logs/steamos-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
STEAM="$HOME/.local/share/Steam"

# Steam client logs (the volume buttons are handled by Steam / gamescope).
for f in console_log.txt console_log.previous.txt controller.txt controller.previous.txt \
         steamui_html.txt webhelper.txt bootstrap_log.txt systemaudio.txt; do
    [ -f "$STEAM/logs/$f" ] && tail -c 4000000 "$STEAM/logs/$f" > "$OUT/$f"
done
# Any other recent Steam logs that mention audio or volume.
find "$STEAM/logs" -maxdepth 1 -name '*.txt' -mmin -240 2>/dev/null | while read -r f; do
    b="$(basename "$f")"; [ -f "$OUT/$b" ] || tail -c 2000000 "$f" > "$OUT/$b"
done

# SteamVR logs.
VRLOGS="$STEAM/logs"
for f in vrserver.txt vrcompositor.txt vrmonitor.txt vrclient_*.txt; do
    for g in $VRLOGS/$f; do [ -f "$g" ] && tail -c 2000000 "$g" > "$OUT/$(basename "$g")"; done
done

# This boot's system journal for the user session (gamescope, PipeWire,
# WirePlumber, Steam) and the key-related kernel lines.
if command -v journalctl >/dev/null; then
    journalctl --user -b --no-pager 2>/dev/null | tail -n 200000 > "$OUT/journal-user.txt"
    journalctl --user -b -u wireplumber -u pipewire -u pipewire-pulse --no-pager 2>/dev/null > "$OUT/journal-audio.txt"
    journalctl -b --no-pager 2>/dev/null | grep -i -E "gamescope|volume|keyboard|input|audio" | tail -n 50000 > "$OUT/journal-system-filtered.txt"
fi

# Current audio state.
command -v wpctl >/dev/null && wpctl status > "$OUT/wpctl-status.txt" 2>&1
command -v pactl >/dev/null && { pactl info; pactl list sinks; pactl list sink-inputs; } > "$OUT/pactl.txt" 2>&1
[ -d "$HOME/.local/state/wireplumber" ] && ls -la "$HOME/.local/state/wireplumber" > "$OUT/wireplumber-state-list.txt" 2>&1 \
    && cp "$HOME/.local/state/wireplumber/"* "$OUT/" 2>/dev/null

# Input devices (which one sends the volume keys).
[ -r /proc/bus/input/devices ] && cat /proc/bus/input/devices > "$OUT/input-devices.txt"

# Mask addresses, ids and names in every copy; one that can't be cleaned is
# left out rather than passed on as it is.
for f in "$OUT"/*; do
    [ -f "$f" ] || continue
    if python3 -I "$HERE/share_log.py" clean "$f" "$f.cleaned" 2>/dev/null; then
        mv -f "$f.cleaned" "$f"
    else
        rm -f "$f" "$f.cleaned"
    fi
done

cd "$(dirname "$OUT")" && tar czf "$(basename "$OUT").tar.gz" "$(basename "$OUT")" && rm -rf "$OUT"
echo "Saved: $OUT.tar.gz (addresses, ids and names masked; still worth a look before posting it publicly)"
command -v notify-send >/dev/null && notify-send "SteamOS logs saved" "$OUT.tar.gz - addresses, ids and names are masked."
