#!/bin/bash
# Nightfall native launcher for the Steam Frame (add this file as a non-Steam game).
# Based on Moonlight XR for Frame's launcher (GPLv3).
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
mkdir -p "$HERE/logs"
# Nightfall's settings folder. Since build 8u it is this port's own
# (override.cfg says why); before, it was the one the original Nightfall's
# Steam Frame build uses too. The first start after updating carries the
# earlier settings over, once, and only if this port wrote them: its own
# options all begin with "frame_", and the original's build writes none. The
# old folder is left as it is.
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/NightfallFrame"
OLD_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Nightfall"
CARRIED=""
if [ ! -e "$DATA" ] && [ -f "$OLD_DATA/app_state.cfg" ] && grep -q '^frame_' "$OLD_DATA/app_state.cfg"; then
    rm -rf "$DATA.partial"
    if mkdir -p "$DATA.partial" && cp -a "$OLD_DATA/." "$DATA.partial/" \
            && rm -rf "$DATA.partial/logs" "$DATA.partial/shader_cache" "$DATA.partial/vulkan" \
            && mv "$DATA.partial" "$DATA"; then
        CARRIED="settings carried over from $OLD_DATA"
    else
        rm -rf "$DATA.partial"
        CARRIED="could not carry the settings over from $OLD_DATA; starting with new ones"
    fi
fi
# The launcher needs two of the saved settings before Nightfall runs.
CFG=""
[ -f "$DATA/app_state.cfg" ] && CFG="$DATA/app_state.cfg"
# Advanced Settings > Logging, as saved. Off: no log of the run, no copy in
# Downloads, no audio snapshot, and Nightfall is told to write none of its
# own (NIGHTFALL_LOGGING). Off on a new install (nothing saved yet); on for
# an install from before the option existed, which has no line for it. A
# file named "logging-on" in this folder turns it on whatever is saved, for
# when Nightfall doesn't get far enough to show its menu.
LOGGING=1
if [ -z "$CFG" ]; then
    LOGGING=0
elif [ "$(sed -n 's/^frame_logging=\(true\|false\).*/\1/p' "$CFG" | head -n 1)" = "false" ]; then
    LOGGING=0
fi
[ -e "$HERE/logging-on" ] && LOGGING=1
export NIGHTFALL_LOGGING=$LOGGING
rm -f "$HERE/logs/last-exit"
STARTED="$(date -Is)"
LOG="$HERE/logs/nightfall-$(date +%Y%m%d-%H%M%S).log"
if [ "$LOGGING" = 1 ]; then
    # keep the newest 10 run logs
    ls -1t "$HERE"/logs/nightfall-*.log 2>/dev/null | tail -n +10 | xargs -r rm -f
    ln -sfn "$LOG" "$HERE/nightfall-console.log"
fi
# Steam injects GL overrides meant for games; they break Mesa for native apps.
unset MESA_GL_VERSION_OVERRIDE MESA_GLSL_VERSION_OVERRIDE
# Use the host's libraries, not Steam's runtime.
unset LD_LIBRARY_PATH
# The Gamescope WSI layer pops an error for the (unused) desktop window; the
# VR view goes through OpenXR swapchains, so keep the layer out of this app.
export ENABLE_GAMESCOPE_WSI=0
# Point at SteamVR's OpenXR runtime only if the default lookup would fail.
if [ ! -e "$HOME/.config/openxr/1/active_runtime.json" ] && [ -e /opt/steamvr/steamxr_linuxarm64.json ]; then
    export XR_RUNTIME_JSON=/opt/steamvr/steamxr_linuxarm64.json
fi
cd "$HERE" || exit 1
# Audio routing snapshot (diagnostics): which PipeWire nodes exist while
# Nightfall runs, so we can see whether SteamOS's spatializer is in the path.
AUDLOG="$HERE/logs/audio-nodes-$(date +%Y%m%d-%H%M%S).txt"
ls -1t "$HERE"/logs/audio-nodes-*.txt 2>/dev/null | tail -n +5 | xargs -r rm -f
[ "$LOGGING" = 1 ] && (
    for t in 45 90 150; do
        sleep $((t - ${prev:-0})); prev=$t
        {
            echo "===== $(date -Is) (+${t}s)"
            command -v wpctl >/dev/null && wpctl status 2>&1 | sed -n '/Audio/,/Video/p'
            command -v pw-cli >/dev/null && pw-cli ls Node 2>&1 | grep -E "^\s*id |node.name|node.description|media.class|application.name|application.process.id|target.object" 
            command -v pactl >/dev/null && pactl list sink-inputs 2>&1 | grep -E "Sink Input|Sink:|application.name|node.name|media.name|application.process.id"
        } >>"$AUDLOG" 2>&1
    done
) &
chmod +x ./Nightfall.arm64 2>/dev/null
# A copy of this run's log in Downloads, easy to attach, and cleaned for
# sharing: network addresses, device ids, keys and names are masked on the
# way (share_log.py says exactly what). The log in logs/ stays as written.
# The copy is kept up to date every 20 seconds while Nightfall runs: made
# only at exit, it was the previous run's whenever a log was fetched with
# Nightfall still open (three wrong logs on 2026-11-14). It is a separate
# file because the ones in logs/ can fail to upload while still being written.
SHARE="$HOME/Downloads/Nightfall-logs"
COPIER=""
if [ "$LOGGING" != 1 ]; then
    : # nothing is put in Downloads; what is there from earlier runs stays
elif ! mkdir -p "$SHARE"; then
    :
elif command -v python3 >/dev/null 2>&1; then
    python3 -I "$HERE/share_log.py" follow "$LOG" "$SHARE/nightfall-latest.log" &
    COPIER=$!
else
    # Nothing is put in Downloads rather than an uncleaned log.
    echo "No log copy for sharing this run: python3 is missing (share_log.py needs it). The log itself is in $HERE/logs/." >"$SHARE/nightfall-latest.log"
fi
# How the graphics driver (Mesa Turnip) draws the 3D scene. It has a tiled
# mode and a direct one. Foveated rendering only works tiled; without
# foveation, tiled costs Nightfall's scene twice the time (13 ms a frame
# against 6, build 6f). So unless Advanced > Foveation is on, ask for direct
# drawing. (Godot's official engine ended up there by accident; the package's
# engine, steam-frame/engine/, lets the driver choose.)
# The driver takes its debug switches from a file it keeps re-reading
# (TU_DEBUG_FILE; "sysmem" is the switch for direct drawing), so the choice
# can follow the Foveation option while Nightfall runs: written here from the
# saved setting, rewritten by Nightfall when the option changes. SteamVR
# points every app at one shared file; Nightfall gets its own.
FOVEATION=0
SETTINGS_READ="no saved settings found"
if [ -n "$CFG" ]; then
    FOVEATION="$(sed -n 's/^frame_foveation=\([0-9]\).*/\1/p' "$CFG" | head -n 1)"
    SETTINGS_READ="read from $CFG"
fi
STEAM_TU_DEBUG_FILE="${TU_DEBUG_FILE:-}"
export NIGHTFALL_TU_DEBUG_FILE="$HERE/logs/turnip-debug.txt"
export TU_DEBUG_FILE="$NIGHTFALL_TU_DEBUG_FILE"
case "$FOVEATION" in
    1|2|3) : >"$TU_DEBUG_FILE"
           DRAW_MODE="foveation level $FOVEATION saved: the driver chooses how to draw (tiled, which foveation needs)" ;;
    *)     printf 'sysmem' >"$TU_DEBUG_FILE"
           DRAW_MODE="foveation off: direct drawing asked for (sysmem)" ;;
esac
run_nightfall() {
    echo "== $(date -Is) launching Nightfall.arm64 (SteamAppId=${SteamAppId:-none})"
    echo "XR_RUNTIME_JSON=${XR_RUNTIME_JSON:-default}"
    echo "[SETTINGS] folder $DATA${CARRIED:+ ($CARRIED)}"
    echo "[DRIVER] $DRAW_MODE ($SETTINGS_READ); switches file $TU_DEBUG_FILE (SteamVR's: ${STEAM_TU_DEBUG_FILE:-none}); SteamVR's own setting TU_AUTOTUNE_FLAGS=${TU_AUTOTUNE_FLAGS:-(none)}"
    ./Nightfall.arm64 --xr-mode on --audio-driver Dummy --verbose "$@"
    CODE=$?   # taken first: the date command below would replace it with its own
    echo "$CODE" >"$HERE/logs/last-exit"
    echo "== $(date -Is) Nightfall exited with $CODE"
}
# The log goes through cap_log.py, which writes a block of lines that keeps
# repeating once and stops at 256 MB: a log once grew by a thousand lines a
# second while the headset lay unworn. Without python3 it is written as it comes.
if [ "$LOGGING" != 1 ]; then
    # Logging is off: only when the run began and how it ended, in one small
    # file that the next run replaces.
    ./Nightfall.arm64 --xr-mode on --audio-driver Dummy "$@" >/dev/null 2>&1
    CODE=$?
    echo "$CODE" >"$HERE/logs/last-exit"
    printf 'Started %s\nEnded %s, exit code %s\nLogging is off: Advanced Settings > Logging turns it on from the next start.\n' \
        "$STARTED" "$(date -Is)" "$CODE" >"$HERE/logs/last-run.txt"
elif command -v python3 >/dev/null 2>&1 && [ -f "$HERE/cap_log.py" ]; then
    run_nightfall "$@" 2>&1 | python3 -I "$HERE/cap_log.py" "$LOG"
else
    run_nightfall "$@" >"$LOG" 2>&1
fi
# The copier adds the last lines when told to stop; then the finished copy
# also goes under the run's own name.
if [ -n "$COPIER" ]; then
    kill "$COPIER" 2>/dev/null
    wait "$COPIER" 2>/dev/null
    cp -f "$SHARE/nightfall-latest.log" "$SHARE/$(basename "$LOG")" 2>/dev/null
fi
ls -1t "$SHARE"/nightfall-2*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
# Exit code 75 is Nightfall asking to be started again (Reset Settings, so
# that nobody has to find it in Steam after resetting). The launcher runs
# itself afresh: the new run gets its own log and reads the settings as they
# now are. At most three times in a row, in case something keeps asking.
if [ "$(cat "$HERE/logs/last-exit" 2>/dev/null)" = 75 ] && [ "${NIGHTFALL_RESTARTS:-0}" -lt 3 ]; then
    export NIGHTFALL_RESTARTS=$(( ${NIGHTFALL_RESTARTS:-0} + 1 ))
    exec "$HERE/nightfall.sh" "$@"
fi
