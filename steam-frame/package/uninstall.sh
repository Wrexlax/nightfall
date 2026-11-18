#!/bin/bash
# Removes Nightfall for Steam Frame from this headset. Double-click it, or
# run it in a terminal (Konsole):  bash ~/Games/NightfallFrame/uninstall.sh
#
# It asks before removing anything, and asks separately about the two things
# worth keeping if Nightfall may be installed again: the voice typing speech
# models (a long download) and your settings and PC pairings.
# WHERE-THINGS-ARE.txt lists every place Nightfall keeps files.
#
#   --yes            no questions: remove the app and its Steam shortcut,
#                    keep the speech models and the settings
#   --models         with --yes: remove the speech models too
#   --settings       with --yes: remove settings and pairings too
#   --dry-run        only say what would be removed
set -u

main() {
    local yes=false models=false settings=false dry=false a
    for a in "$@"; do
        case "$a" in
            --yes) yes=true ;;
            --models) models=true ;;
            --settings) settings=true ;;
            --dry-run) dry=true ;;
            *) echo "unknown option: $a (see the top of this file)"; return 2 ;;
        esac
    done
    [ -n "${HOME:-}" ] && [ -d "$HOME" ] || { echo "no home folder; nothing done"; return 1; }

    # The same places install.sh and nightfall.sh use.
    local dest="$HOME/Games/NightfallFrame"
    local name="Nightfall (Steam Frame)"
    local install_log="$HOME/Games/nightfall-install.log"
    local shared_logs="$HOME/Downloads/Nightfall-logs"
    local models_dir="$HOME/.local/share/nightfall"
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/NightfallFrame"
    # Where builds before 8u kept the settings. The original Nightfall's
    # Steam Frame build uses this folder too, so it is only removed when the
    # settings in it are this port's (its own options begin with "frame_").
    local old_data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Nightfall"
    local old_is_ours=false
    grep -q '^frame_' "$old_data_dir/app_state.cfg" 2>/dev/null && old_is_ours=true
    local here
    here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

    if pgrep -x Nightfall.arm64 >/dev/null 2>&1; then
        tell "Nightfall is running. Close it first, then run the uninstaller again."
        return 1
    fi

    if [ "$yes" = false ]; then
        ask "Remove Nightfall from this headset?

This removes the app ($dest), its entry in your Steam library and its logs.

You are asked about the speech models and your settings next." || { echo "nothing removed"; return 0; }
        if [ -d "$models_dir" ]; then
            ask "Also remove the voice typing speech models ($(size_of "$models_dir"))?

Choose No if you may install Nightfall again: they would have to be downloaded again." && models=true
        fi
        if [ -d "$data_dir" ] || [ "$old_is_ours" = true ]; then
            ask "Also remove your Nightfall settings, your button mappings and profiles, and your PC pairings?

Choose No if you may install Nightfall again. With Yes, each PC has to be paired again and buttons you set up are gone." && settings=true
        fi
    fi

    # The Steam shortcut first: the helper that talks to Steam is in the app's
    # folder. Steam is asked to remove it, then asked again whether it is gone.
    local shortcut_msg="" cef="$dest/steam_cef.py"
    [ -f "$cef" ] || cef="$here/steam_cef.py"
    if [ "$dry" = true ]; then
        echo "would remove: the Steam library entry \"$name\""
    elif [ -f "$cef" ] && command -v python3 >/dev/null 2>&1; then
        local left
        left="$(python3 -I "$cef" "(async()=>{
  const name='$name';
  const mine=()=>[...appStore.allApps].filter(a=>a.app_type===1073741824 && a.display_name===name);
  for (const a of mine()) SteamClient.Apps.RemoveShortcut(a.appid);
  await new Promise(r=>setTimeout(r,1500));
  return mine().length;
})()" 2>/dev/null)"
        if [ "$left" = "0" ]; then
            shortcut_msg="Removed from your Steam library."
        else
            shortcut_msg="The Steam library entry could not be removed from here. In Steam: \"$name\" > Manage > Remove non-Steam game from your library."
        fi
    else
        shortcut_msg="The Steam library entry was not touched. In Steam: \"$name\" > Manage > Remove non-Steam game from your library."
    fi

    remove "$dest" "$dry"
    remove "$install_log" "$dry"
    remove "$shared_logs" "$dry"
    local kept=""
    if [ "$models" = true ]; then
        remove "$models_dir" "$dry"
    elif [ -d "$models_dir" ]; then
        kept="$kept
  - speech models: $models_dir"
    fi
    if [ "$settings" = true ]; then
        remove "$data_dir" "$dry"
        [ "$old_is_ours" = true ] && remove "$old_data_dir" "$dry"
    elif [ -d "$data_dir" ]; then
        kept="$kept
  - settings and pairings: $data_dir"
    fi
    # ~/Games is only removed if Nightfall was the last thing in it.
    [ "$dry" = false ] && rmdir "$HOME/Games" 2>/dev/null

    [ "$dry" = true ] && return 0
    tell "Nightfall has been removed.

$shortcut_msg
${kept:+
Kept, for a later install (delete these folders yourself to remove them):$kept
}
SteamVR keeps a few video settings it stored for Nightfall; they do nothing without the app."
}

# Removes one file or folder of Nightfall's. Only ever a path inside the home
# folder, never the home folder itself.
remove() {   # remove <path> <dry-run true|false>
    local path="$1"
    case "$path" in
        "$HOME"/?*) ;;
        *) echo "not removing $path: outside the home folder"; return 1 ;;
    esac
    [ -e "$path" ] || return 0
    if [ "$2" = true ]; then
        echo "would remove: $path ($(size_of "$path"))"
    else
        rm -rf -- "$path" && echo "removed: $path"
    fi
}

size_of() { du -sh -- "$1" 2>/dev/null | cut -f1; }

# A yes/no question: a dialog on the desktop, the terminal otherwise.
ask() {
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v kdialog >/dev/null 2>&1; then
        kdialog --title "Remove Nightfall" --yesno "$1"
    elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
        zenity --question --title="Remove Nightfall" --text="$1"
    elif [ -t 0 ]; then
        local answer
        printf '%s\n[y/N] ' "$1"
        read -r answer
        [ "$answer" = "y" ] || [ "$answer" = "Y" ]
    else
        echo "No way to ask (no desktop, no terminal). Run with --yes to go ahead."
        return 1
    fi
}

tell() {
    echo "$1"
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v kdialog >/dev/null 2>&1; then
        kdialog --title "Nightfall" --msgbox "$1" >/dev/null 2>&1 &
    elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
        zenity --info --title="Nightfall" --text="$1" >/dev/null 2>&1 &
    fi
}

# Everything above is read before anything runs: this script deletes the
# folder it is in.
main "$@"
exit $?
