#!/bin/bash
# Nightfall for Steam Frame installer.
# Copies this folder to ~/Games/NightfallFrame and adds (or updates) the Steam
# library shortcut "Nightfall (Steam Frame)" through Steam's local CEF debugging
# port, the same way Moonlight XR for Frame's installer does (steam_cef.py is
# from that project, GPLv3). Run it from a terminal on the Frame with Steam running.
set -u
# --leave-shortcut: don't touch an existing Steam shortcut or its artwork
# (test for the volume-button runaway after reinstalling).
LEAVE=false
for a in "$@"; do [ "$a" = "--leave-shortcut" ] && LEAVE=true; done
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST="$HOME/Games/NightfallFrame"
NAME="Nightfall (Steam Frame)"
LOG="$HOME/Games/nightfall-install.log"
mkdir -p "$HOME/Games"
exec > >(tee "$LOG") 2>&1
# The package keeps everything but this installer, the uninstaller and the
# readme in a folder called "files". The installed copy in ~/Games has no
# such folder (it is run from there to fetch a speech model again), and
# neither had the packages up to build 8e.
SRC="$HERE/files"
[ -d "$SRC" ] || SRC="$HERE"
BUILD="$(cat "$SRC/VERSION" 2>/dev/null || echo "?")"
echo "== $(date -Is) installing Nightfall build $BUILD from $HERE to $DEST"
VOICE_MSG=""
STEAM_MSG=""
command -v notify-send >/dev/null 2>&1 && notify-send "Installing Nightfall build $BUILD..." "This takes a few seconds. The first time it also downloads the voice typing models (about 600 MB), which can take several minutes: a window shows how far it is." >/dev/null 2>&1
if [ "$(readlink -f "$HERE")" != "$(readlink -f "$DEST")" ]; then
    mkdir -p "$DEST"
    cp -a "$SRC/." "$DEST/" || { echo "copy failed"; exit 1; }
    # The stream library is named after the kind of engine it goes with
    # (debug or release). An install over a build with the other kind would
    # keep the old library (41 MB) for nothing.
    for kind in debug release; do
        lib="addons/nightfall-stream/bin/linux/libnightfall-stream.linux.template_$kind.arm64.so"
        [ -f "$SRC/$lib" ] || rm -f "$DEST/$lib"
    done
    if [ "$SRC" != "$HERE" ]; then
        cp -a "$HERE/install.sh" "$HERE/uninstall.sh" "$HERE/README.txt" "$DEST/" || { echo "copy failed"; exit 1; }
    fi
fi
chmod +x "$DEST/nightfall.sh" "$DEST/Nightfall.arm64" "$DEST/install.sh" "$DEST/uninstall.sh" "$DEST/collect-steamos-logs.sh"
# Gone from the package in 8f (it would only confuse); an
# older install still has it. install.sh --leave-shortcut does the same.
rm -f "$DEST/install-files-only.sh"
# Left behind by test builds 5y to 6b (tries at foveated rendering); an
# install copies over the old one, so they would stay otherwise.
rm -f "$DEST/probe-vulkan-layers.sh" "$DEST/logs/vulkan-layer-probe.txt" "$DEST/logs/vulkan-layer-try" "$DEST/logs/vulkan-layer-run" "$DEST/logs/foveation-run"
if [ -d "$DEST/vulkan-layers" ]; then
    rm -f "$DEST/vulkan-layers/VkLayer_VALVE_fdm_injection.json" "$DEST/vulkan-layers/VkLayer_VALVE_rpo.json" "$DEST/vulkan-layers"/fdm-switch-*
    rmdir "$DEST/vulkan-layers" 2>/dev/null
fi
if head -n 1 "$DEST/override.cfg" 2>/dev/null | grep -q -F '; Nightfall foveation test'; then
    rm -f "$DEST/override.cfg"   # written by 6b to 6e's test runs
fi
echo "files installed in $DEST"

# --- Speech models for voice typing -----------------------------------------
# The only downloads of the install. They finish (or fail) before the window
# with "Restart now" appears, so that button can't cut one off.

# A window with a progress bar while a model downloads (KDE's kdialog, driven
# over D-Bus). A download of several minutes used to show one notification
# and then nothing, which looks like a hang. Without kdialog or qdbus there is
# no window and the notification stands in; the download is the same.
PROGRESS_REF=""
PROGRESS_BUS=""
progress_start() {
    PROGRESS_REF=""
    for PROGRESS_BUS in qdbus6 qdbus qdbus-qt6 qdbus-qt5; do
        command -v "$PROGRESS_BUS" >/dev/null 2>&1 && break
        PROGRESS_BUS=""
    done
    if [ -n "$PROGRESS_BUS" ] && command -v kdialog >/dev/null 2>&1; then
        PROGRESS_REF="$(kdialog --title "Installing Nightfall" --progressbar "$1" 100 2>/dev/null)"
    fi
    if [ -z "$PROGRESS_REF" ]; then
        command -v notify-send >/dev/null 2>&1 && notify-send "Installing Nightfall" "$1" >/dev/null 2>&1
    fi
    return 0
}
progress_set() {
    # $PROGRESS_REF is two words on purpose: the service and the object.
    [ -n "$PROGRESS_REF" ] && "$PROGRESS_BUS" $PROGRESS_REF Set "" value "$1" >/dev/null 2>&1
    return 0
}
progress_stop() {
    [ -n "$PROGRESS_REF" ] && "$PROGRESS_BUS" $PROGRESS_REF close >/dev/null 2>&1
    PROGRESS_REF=""
    return 0
}

# fetch_model <what it is, for the window> <file> <sha1> <url> <size in MB>
# Downloads to <file>.partial and moves it into place only after it matches
# the SHA-1 that whisper.cpp publishes (models/README.md); a file that doesn't
# match is deleted, never used. An interrupted download keeps its partial
# file, and the next run carries on from there instead of starting over.
# Returns 0: installed; 1: couldn't download (partial kept); 2: failed its
# check (deleted).
fetch_model() {
    local label="$1" file="$2" sha1="$3" url="$4" mb="$5"
    local part="$2.partial" total have watcher rc resumed=0
    rm -f "$file"
    if [ -s "$part" ] && [ "$(sha1sum "$part" | cut -d' ' -f1)" = "$sha1" ]; then
        # All of it arrived last time and only the last step was cut off.
        mv "$part" "$file"
        chmod 644 "$file"
        echo "$label: the earlier download was complete; verified and installed"
        return 0
    fi
    if [ -s "$part" ]; then
        resumed=1
        echo "carrying on an earlier download of $label ($(( $(stat -c %s "$part") / 1048576 )) MB already here)"
    fi
    total="$(curl -sIL --max-time 20 "$url" 2>/dev/null | tr -d '\r' | awk 'tolower($1)=="content-length:" {n=$2} END {print n+0}')"
    [ "${total:-0}" -gt 1000000 ] 2>/dev/null || total=$((mb * 1048576))
    progress_start "Downloading $label ($mb MB, once). Please wait: the installer carries on by itself."
    (
        while :; do
            sleep 1
            have="$(stat -c %s "$part" 2>/dev/null || echo 0)"
            progress_set $((have * 100 / total))
        done
    ) &
    watcher=$!
    curl -fL --retry 3 --retry-delay 2 -C - -o "$part" "$url"
    rc=$?
    if [ $rc -ne 0 ] && [ $resumed -eq 1 ]; then
        # The partial couldn't be continued (it was already whole or damaged,
        # or the server wouldn't): once more from the start.
        echo "the earlier partial download couldn't be continued (curl $rc); starting over"
        rm -f "$part"
        curl -fL --retry 3 --retry-delay 2 -o "$part" "$url"
        rc=$?
    fi
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    progress_stop
    if [ $rc -ne 0 ]; then
        echo "couldn't download $label (curl $rc); what arrived is kept for the next run"
        return 1
    fi
    if [ "$(sha1sum "$part" | cut -d' ' -f1)" != "$sha1" ]; then
        rm -f "$part"
        echo "$label failed its check and was deleted"
        return 2
    fi
    mv "$part" "$file"
    chmod 644 "$file"
    echo "$label installed and verified"
    return 0
}

# The two models, both from whisper.cpp's official model page:
# base.en (English, 142 MB): quick. small.en (466 MB): hears words more
# correctly, takes longer per sentence (Advanced Settings > Speech Model).
VOICE_PROBLEM=""   # goes at the very top of the final window
WDIR="$HOME/.local/share/nightfall/whisper"
WMODEL="$WDIR/ggml-base.en.bin"
WSHA1="137c40403d78fd54d454da0f9bd998f78703390c"
WURL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
WSMALL="$WDIR/ggml-small.en.bin"
WSMALL_SHA1="db8a495a91d927739e50b3fc1cc4c6b8f6c2d022"
WSMALL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
mkdir -p "$WDIR"

# Which kind of speech model: Nightfall listens in the language its menu is
# set to (8l). The English-only models hear English best; the multilingual
# ones are the same sizes and know the menu's other languages (and English).
# SHA-1 of each from whisper.cpp's models/README.md.
has_model() { [ -f "$WDIR/$1" ] && [ "$(sha1sum "$WDIR/$1" | cut -d' ' -f1)" = "$2" ]; }
installed_models() {
    local list=""
    has_model ggml-base.en.bin 137c40403d78fd54d454da0f9bd998f78703390c && list="$list, English Base"
    has_model ggml-small.en.bin db8a495a91d927739e50b3fc1cc4c6b8f6c2d022 && list="$list, English Small"
    has_model ggml-base.bin 465707469ff3a37a2b9b8d8f89f2f99de7299dac && list="$list, multilingual Base"
    has_model ggml-small.bin 55356645c2b361a969dfd0ef2c5a50d530afd8d5 && list="$list, multilingual Small"
    echo "${list#, }"
}
language_choice() {   # prints english or other
    local last="$1" answer="" on_en=off on_other=off
    [ "$last" = other ] && on_other=on || on_en=on
    local have; have="$(installed_models)"
    local text="Which language will you speak to Nightfall? It listens in the language its menu is set to (Advanced Settings > Language). Installed now: ${have:-no speech model}."
    local en="English: the English-only speech models, which hear English best"
    local other="Another language: the multilingual speech models (same sizes; they hear English too)"
    if command -v kdialog >/dev/null 2>&1; then
        answer="$(kdialog --title "Installing Nightfall" --radiolist "$text" english "$en" $on_en other "$other" $on_other 2>/dev/null)" || answer="$last"
    elif command -v zenity >/dev/null 2>&1; then
        answer="$(zenity --list --radiolist --title="Installing Nightfall" --text="$text" --width=760 --height=260 \
            --column="" --column="choice" --column="Language" --hide-column=2 --print-column=2 \
            "$([ $on_en = on ] && echo TRUE || echo FALSE)" english "$en" \
            "$([ $on_other = on ] && echo TRUE || echo FALSE)" other "$other" 2>/dev/null)" || answer="$last"
    elif [ -t 0 ]; then
        echo "$text" >&2
        echo "  1) $en" >&2; echo "  2) $other" >&2
        read -r -p "1 or 2 [Enter: $last]: " answer
        case "$answer" in 1) answer=english ;; 2) answer=other ;; *) answer="$last" ;; esac
    else
        answer="$last"   # nobody to ask
    fi
    case "$answer" in english|other) echo "$answer" ;; *) echo "$last" ;; esac
}
WKIND_FILE="$WDIR/language"
WKIND="$(cat "$WKIND_FILE" 2>/dev/null)"
WKIND_ASK=false
# The language Nightfall's menu is set to, if it has been set ("" otherwise).
MENU_LANGUAGE=""
for cfg in "${XDG_DATA_HOME:-$HOME/.local/share}/NightfallFrame/app_state.cfg" \
           "${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Nightfall/app_state.cfg"; do
    [ -f "$cfg" ] && MENU_LANGUAGE="$(sed -n 's/^language="\([A-Za-z_]*\)".*/\1/p' "$cfg" | head -n 1)" && break
done
if [ "$WKIND" != english ] && [ "$WKIND" != other ]; then
    # Never asked: go by the menu's language, or the headset's own.
    case "${MENU_LANGUAGE:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}" in en*|C|C.*|POSIX|""|auto|system) WKIND=english ;; *) WKIND=other ;; esac
fi
# Asked again when the models of the kind chosen last time aren't all here
# (the next question is about them), or when the menu has since been put
# into another language than English with only English models chosen.
if [ "$WKIND" = english ]; then
    { has_model ggml-base.en.bin 137c40403d78fd54d454da0f9bd998f78703390c && has_model ggml-small.en.bin db8a495a91d927739e50b3fc1cc4c6b8f6c2d022; } || WKIND_ASK=true
    case "$MENU_LANGUAGE" in ""|en*|auto|system) : ;; *) WKIND=other; WKIND_ASK=true ;; esac
else
    { has_model ggml-base.bin 465707469ff3a37a2b9b8d8f89f2f99de7299dac && has_model ggml-small.bin 55356645c2b361a969dfd0ef2c5a50d530afd8d5; } || WKIND_ASK=true
fi
# --speech-models (the "Speech models" button of the last window): ask again
# whatever is installed. Without it there was no way to add the models for
# another language once the English ones were complete, short of deleting
# them (8l).
case " $* " in *" --speech-models "*) WKIND_ASK=true ;; esac
for a in "$@"; do case "$a" in --voice-language=english|--voice-language=other) WKIND="${a#--voice-language=}"; WKIND_ASK=false ;; esac; done
case " $* " in *" --models="*) WKIND_ASK=false ;; esac
$WKIND_ASK && WKIND="$(language_choice "$WKIND")"
printf '%s\n' "$WKIND" > "$WKIND_FILE"
echo "speech model kind: $WKIND (installed: $(installed_models))"
if [ "$WKIND" = other ]; then
    WMODEL="$WDIR/ggml-base.bin"
    WSHA1="465707469ff3a37a2b9b8d8f89f2f99de7299dac"
    WURL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
    WSMALL="$WDIR/ggml-small.bin"
    WSMALL_SHA1="55356645c2b361a969dfd0ef2c5a50d530afd8d5"
    WSMALL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
fi
HAVE_BASE=false; HAVE_SMALL=false
[ -f "$WMODEL" ] && [ "$(sha1sum "$WMODEL" | cut -d' ' -f1)" = "$WSHA1" ] && HAVE_BASE=true
[ -f "$WSMALL" ] && [ "$(sha1sum "$WSMALL" | cut -d' ' -f1)" = "$WSMALL_SHA1" ] && HAVE_SMALL=true

# Which to download is the user's choice, none included: both, Base alone, or
# none. Asked whenever one is missing, with the last answer already selected,
# so an update is one press of Enter for someone who chose Base alone or
# none. --models=both|base|none answers it ahead of time. Closing the
# question downloads nothing this time and keeps what is installed.
model_choice() {
    local last="$1" on_both=off on_base=off on_none=off answer
    case "$last" in base) on_base=on ;; none) on_none=on ;; *) on_both=on ;; esac
    # What is on the headset already is checked first (each file against its
    # SHA-1) and said in the question; nothing that is there is downloaded
    # again, and nothing is ever deleted by a choice.
    local have="neither is installed yet"
    $HAVE_BASE && have="Base is already installed; Small is not"
    $HAVE_SMALL && ! $HAVE_BASE && have="Small is already installed; Base is not"
    local kind="English-only"; [ "$WKIND" = other ] && kind="multilingual"
    have="$have, of the $kind models"
    local text="On-headset voice typing: Nightfall turns what you say into text on the headset itself. It needs a speech model, downloaded once (now: $have). Without one, the keyboard's Mic key uses Windows dictation on the PC. Which do you want?"
    local both="Base and Small (about 610 MB together): Small hears words more correctly, Base is quicker; you can switch in the menu"
    local base="Base only (142 MB)"
    local none="None: no on-headset voice typing (the keyboard's Mic key opens Windows dictation)"
    $HAVE_BASE && both="Base and Small: adds Small (466 MB), which hears words more correctly; you can switch in the menu" && base="Base only: nothing to download"
    $HAVE_SMALL && ! $HAVE_BASE && both="Base and Small: adds Base (142 MB), which is quicker; you can switch in the menu"
    { $HAVE_BASE || $HAVE_SMALL; } && none="Nothing more: keep what is installed"
    if command -v kdialog >/dev/null 2>&1; then
        answer="$(kdialog --title "Installing Nightfall" --radiolist "$text" both "$both" $on_both base "$base" $on_base none "$none" $on_none 2>/dev/null)" || answer="skip"
    elif command -v zenity >/dev/null 2>&1; then
        answer="$(zenity --list --radiolist --title="Installing Nightfall" --text="$text" --width=760 --height=300 \
            --column="" --column="choice" --column="Speech models" --hide-column=2 --print-column=2 \
            "$([ $on_both = on ] && echo TRUE || echo FALSE)" both "$both" \
            "$([ $on_base = on ] && echo TRUE || echo FALSE)" base "$base" \
            "$([ $on_none = on ] && echo TRUE || echo FALSE)" none "$none" 2>/dev/null)" || answer="skip"
    elif [ -t 0 ]; then
        echo "$text" >&2
        echo "  1) $both" >&2; echo "  2) $base" >&2; echo "  3) $none" >&2
        read -r -p "1, 2 or 3 [Enter: as last time]: " answer
        case "$answer" in 1) answer=both ;; 2) answer=base ;; 3) answer=none ;; *) answer="${last:-both}" ;; esac
    else
        answer="${last:-both}"   # nobody to ask
    fi
    case "$answer" in both|base|none|skip) echo "$answer" ;; *) echo skip ;; esac
}
WCHOICE_FILE="$WDIR/choice"
WLAST="$(cat "$WCHOICE_FILE" 2>/dev/null)"
WANT=""
for a in "$@"; do case "$a" in --models=both|--models=base|--models=none) WANT="${a#--models=}" ;; esac; done
if $HAVE_BASE && $HAVE_SMALL; then
    WANT="${WANT:-both}"
    echo "both voice typing models already installed"
elif [ -z "$WANT" ]; then
    WANT="$(model_choice "$WLAST")"
fi
echo "speech models: $WANT (last time: ${WLAST:-not asked}; installed: base $HAVE_BASE, small $HAVE_SMALL)"
[ "$WANT" != skip ] && printf '%s\n' "$WANT" > "$WCHOICE_FILE"

if { [ "$WANT" = both ] || [ "$WANT" = base ]; } && ! $HAVE_BASE; then
    echo "downloading the voice typing model (142 MB) to $WDIR ..."
    fetch_model "the voice typing model" "$WMODEL" "$WSHA1" "$WURL" 142
    case $? in
        0) HAVE_BASE=true; VOICE_MSG="Voice typing model downloaded and verified." ;;
        2) VOICE_PROBLEM="VOICE TYPING IS OFF: its speech model failed its check after downloading and was deleted. Everything else works. Run the installer again to fetch it." ;;
        *) VOICE_PROBLEM="VOICE TYPING IS OFF: its speech model couldn't be downloaded (is the headset online?). Everything else works. Run the installer again: it carries on from where the download stopped." ;;
    esac
fi
# Free space where the models are kept, in MB. The larger model is only
# fetched with 1 GB to spare: a full disk would stop the download part-way,
# and a nearly full one is no place for it.
WFREE_MB="$(df -Pm "$WDIR" 2>/dev/null | awk 'NR==2 {print $4}')"
if [ "$WANT" = both ] && ! $HAVE_SMALL; then
    if [ -n "$VOICE_PROBLEM" ]; then
        echo "the larger voice typing model is left for the next run, with the one that failed"
    elif [ -n "$WFREE_MB" ] && [ "$WFREE_MB" -lt 1024 ]; then
        echo "only $WFREE_MB MB free in $WDIR: the larger voice typing model (466 MB) was not downloaded; Base stays in use"
        VOICE_MSG="${VOICE_MSG:+$VOICE_MSG }Only $WFREE_MB MB of space is free, so the larger voice typing model (466 MB) was not downloaded."
    else
        echo "downloading the larger voice typing model (466 MB) to $WDIR ..."
        if fetch_model "the larger voice typing model" "$WSMALL" "$WSMALL_SHA1" "$WSMALL_URL" 466; then
            HAVE_SMALL=true
            VOICE_MSG="${VOICE_MSG:+$VOICE_MSG }Larger voice typing model downloaded and verified (Advanced Settings > Speech Model)."
        else
            echo "the larger voice typing model was not installed; Base stays in use"
            VOICE_MSG="${VOICE_MSG:+$VOICE_MSG }The larger voice typing model could not be downloaded; run the installer again later and it carries on from where it stopped."
        fi
    fi
fi
# A model of the kind asked for this time that didn't arrive is no reason to
# say voice typing is off while models of the other kind are installed.
if [ -n "$VOICE_PROBLEM" ] && [ -n "$(installed_models)" ]; then
    VOICE_PROBLEM="${VOICE_PROBLEM/VOICE TYPING IS OFF: its speech model/A SPEECH MODEL WAS NOT INSTALLED: it}"
    VOICE_PROBLEM="${VOICE_PROBLEM/Everything else works./Voice typing goes on with what is installed ($(installed_models)).}"
fi
if [ -z "$(installed_models)" ] && [ -z "$VOICE_PROBLEM" ]; then
    # None by choice, or the question was closed with nothing installed.
    VOICE_MSG="On-headset voice typing was not installed (no speech model). Run the installer again whenever you want to add it; the keyboard's Mic key opens Windows dictation meanwhile."
fi
EXE="\"$DEST/nightfall.sh\""
DIR="\"$DEST\""
if APPID=$(python3 -I "$DEST/steam_cef.py" "(async()=>{
  const name='$NAME';
  const shortcuts=[...appStore.allApps].filter(a=>a.app_type===1073741824);
  const have=shortcuts.find(a=>a.display_name===name);
  // An existing shortcut is left exactly as it is: touching it on every
  // reinstall seemed to leave the headset volume buttons running away until
  // a restart (2026-11-08), so only a new shortcut gets its settings.
  if (have && $LEAVE) return have.appid;
  const id = have ? have.appid : await SteamClient.Apps.AddShortcut(name, '$DEST/nightfall.sh', '$DEST', '');
  SteamClient.Apps.SetShortcutName(id, name);
  SteamClient.Apps.SetShortcutExe(id, '$EXE'.replace(/'/g,''));
  SteamClient.Apps.SetShortcutStartDir(id, '$DIR'.replace(/'/g,''));
  return id;
})()" 2>&1); then
    echo "Steam shortcut \"$NAME\" added/updated (appid $APPID)."
    # Library artwork (capsule, header, hero, logo) and icon. Types follow
    # SteamClient.Apps.SetCustomArtworkForApp: 0 capsule, 1 hero, 2 logo, 3 header.
    ART_SUM="$(cat "$DEST"/art/*.png 2>/dev/null | md5sum | cut -d' ' -f1)"
    if [ "$LEAVE" = true ]; then
        echo "Library artwork left as it is (files-only install)."
    elif [ -d "$DEST/art" ]; then
        if python3 -I - "$APPID" "$DEST/art" <<'PY' | python3 -I "$DEST/steam_cef.py" - >/dev/null 2>&1; then
import base64, json, sys
appid, art = int(json.loads(sys.argv[1])), sys.argv[2]
parts = []
for name, kind in (("capsule", 0), ("hero", 1), ("logo", 2), ("header", 3)):
    data = base64.b64encode(open(f"{art}/{name}.png", "rb").read()).decode()
    parts.append(f"try{{await SteamClient.Apps.SetCustomArtworkForApp({appid}, '{data}', 'png', {kind});}}catch(e){{}}")
parts.append(f"try{{SteamClient.Apps.SetShortcutIcon({appid}, {json.dumps(art + '/icon.png')});}}catch(e){{}}")
print("(async()=>{" + "".join(parts) + "return true;})()")
PY
            echo "Library artwork set."
            echo "$ART_SUM" > "$DEST/.art_set"
        else
            echo "Could not set the library artwork (the shortcut still works)."
        fi
    fi
    # SteamVR's video settings for Nightfall alone (SteamVR keeps them per
    # app, under steam.app.<appid> in steamvr.vrsettings):
    #   resolution 3408 per eye   the most SteamVR allows on the Frame; a
    #                             screen drawn by Nightfall (curved, 3D Scene)
    #                             is only as sharp as this
    #   refresh rate 72 Hz        what Nightfall streams at and is tuned for
    # A setting that is already there is left alone, so a choice made in
    # SteamVR's own menu survives reinstalling. They are set through the
    # running SteamVR (vrcmd), as Moonlight XR for Frame's installer does.
    #
    #   motion smoothing off      with it on, SteamVR holds the app at half
    #                             rate whenever a frame runs a little late
    # motionSmoothingOverride: 0 is "Use global setting" and 2 is Off, both
    # read back from the headset on 2026-11-14 after choosing them in
    # SteamVR's per-app screen. 5n to 5r wrote 0 (as Moonlight XR's installer
    # does) and called it off, so a 0 found here is replaced like no setting.
    # Any other number is the user's own choice and is kept.
    # vrpreferences.json in this folder asks for the same three settings the
    # documented way; whether SteamVR reads it for a non-Steam shortcut isn't
    # confirmed.
    VRCMD=/opt/steamvr/bin/linuxarm64/vrcmd
    VRSET="$HOME/.config/openvr/config/steamvr.vrsettings"
    APPNUM="$(python3 -I -c 'import json,sys; print(int(json.loads(sys.argv[1])))' "$APPID" 2>/dev/null)"
    vr_line() { VR_PARTS="${VR_PARTS:+$VR_PARTS
}  - $1"; }
    steamvr_setting() {   # steamvr_setting <key> <value> <words when set> <name> ; adds a line to VR_PARTS
        local have
        have="$(python3 -I -c '
import json, sys
try:
    block = json.load(open(sys.argv[1])).get("steam.app." + sys.argv[2], {})
    value = block.get(sys.argv[3])
    print("" if value is None else int(value))
except Exception:
    print("")' "$VRSET" "$APPNUM" "$1" 2>/dev/null)"
        if [ "$have" = "$2" ]; then
            vr_line "$4: $3"
        elif [ -n "$have" ]; then
            vr_line "$4: $have (your own setting, kept)"
        elif env -u LD_LIBRARY_PATH timeout 20 "$VRCMD" --set-settings-int "steam.app.$APPNUM.$1" "$2" >/dev/null 2>&1; then
            vr_line "$4: $3"
        else
            vr_line "$4: not set (SteamVR refused)"
        fi
    }
    steamvr_value() {   # steamvr_value <key> ; prints the app's own value, or nothing
        python3 -I -c '
import json, sys
try:
    value = json.load(open(sys.argv[1])).get("steam.app." + sys.argv[2], {}).get(sys.argv[3])
    print("" if value is None else int(value))
except Exception:
    print("")' "$VRSET" "$APPNUM" "$1" 2>/dev/null
    }
    VR_PARTS=""
    if [ -n "$APPNUM" ] && [ -x "$VRCMD" ] && pgrep -x vrserver >/dev/null; then
        steamvr_setting resolutionOverride 3408 "3408 per eye (the maximum)" "Resolution"
        steamvr_setting preferredRefreshRate 72 "72 Hz" "Refresh rate"
        case "$(steamvr_value motionSmoothingOverride)" in
            2)    vr_line "Motion smoothing: Off" ;;
            ""|0) if env -u LD_LIBRARY_PATH timeout 20 "$VRCMD" --set-settings-int "steam.app.$APPNUM.motionSmoothingOverride" 2 >/dev/null 2>&1; then
                      vr_line "Motion smoothing: Off"
                  else
                      vr_line "Motion smoothing: not set (SteamVR refused)"
                  fi ;;
            *)    vr_line "Motion smoothing: your own setting, kept" ;;
        esac
        # Frame throttling (SteamVR: Frame Limit > Throttling Behavior) is only
        # reported, never changed. No setting stored is SteamVR's Auto, which
        # held Nightfall to 72 frames a second on a 144 Hz display; 0 is no
        # throttling (both read back from the headset on 2026-11-14).
        case "$(steamvr_value framesToThrottle)" in
            "") vr_line "Frame throttling: Auto (SteamVR's default; at 144 Hz it keeps Nightfall to 72 a second)" ;;
            0)  vr_line "Frame throttling: none" ;;
            *)  vr_line "Frame throttling: your own setting, kept" ;;
        esac
        VR_MSG="SteamVR settings for Nightfall:
$VR_PARTS"
    else
        VR_MSG="SteamVR wasn't running, so its settings for Nightfall were left as they are. Run this installer again with SteamVR up to set them."
    fi
    echo "$VR_MSG"
    echo "Launch \"$NAME\" from your Steam library in the headset (under Non-Steam games)."
    STEAM_MSG="Find \"$NAME\" in your Steam library, under Non-Steam games."
    echo "Tip: restart the headset once after installing a new build - SteamOS can"
    echo "otherwise get stuck repeating the headset volume buttons (a SteamOS bug)."
else
    echo "Could not reach Steam to add the shortcut: $APPID"
    STEAM_MSG="Couldn't reach Steam to add the library shortcut. Make sure Steam is running, then run the installer again."
    echo "Make sure Steam is running, then run this installer again."
fi
echo "log: $LOG"

# Tell the user it's done (the installer is usually started by double-click,
# with no terminal to read).
# What the PC needs, for someone installing for the first time.
PC_MSG="On your PC, have a streaming host running: Sunshine, or its variants Apollo or Vibepollo. Nightfall Meteor on the PC is optional: it adds AI 3D and the headset microphone, and it includes a streaming host of its own if you would rather not install one."
SUMMARY="${VOICE_PROBLEM:+$VOICE_PROBLEM

}Nightfall build $BUILD is installed.

$STEAM_MSG

$PC_MSG
${VOICE_MSG:+
$VOICE_MSG
}${VR_MSG:+
$VR_MSG
}
Restart the headset once after installing, so SteamOS doesn't get stuck repeating the volume buttons. \"Restart now\" does that for you; \"Later\" leaves it to you.
\"Speech models\" asks again which language you will speak to Nightfall, to add the models for another one (nothing installed is removed).

Details: $LOG"

# Restarts the headset the way the desktop's own Restart does: by asking the
# system's login service, which lets the person sitting at the machine do it
# without a password. If that is refused, the desktop is asked instead, and
# if nothing works a window says so rather than leaving the user waiting.
restart_headset() {
    echo "== $(date -Is) restart asked for from the installer's window" >>"$LOG"
    sync
    systemctl reboot >>"$LOG" 2>&1 && return 0
    for bus in qdbus6 qdbus; do
        command -v "$bus" >/dev/null 2>&1 || continue
        "$bus" org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot >>"$LOG" 2>&1 && return 0
    done
    echo "== the headset could not be restarted from here" >>"$LOG"
    if command -v kdialog >/dev/null 2>&1; then
        kdialog --title "Nightfall installed" --sorry "The headset didn't restart from here. Please restart it from the Steam menu (Power)." >/dev/null 2>&1
    elif command -v zenity >/dev/null 2>&1; then
        zenity --warning --title="Nightfall installed" --text="The headset didn't restart from here. Please restart it from the Steam menu (Power)." >/dev/null 2>&1
    fi
    return 1
}

# The window stays up in the background so that the installer itself can
# finish; its "Restart now" button (2026-11-15) answers
# yes, anything else (Later, or closing the window) no.
# "Speech models" runs the installed copy of this script again with the
# speech model questions asked afresh (and the Steam shortcut left alone).
again_for_speech_models() { exec bash "$DEST/install.sh" --speech-models --leave-shortcut; }
if command -v kdialog >/dev/null 2>&1; then
    ( kdialog --title "Nightfall installed" --yes-label "Restart now" --no-label "Speech models" --cancel-label "Later" --yesnocancel "$SUMMARY"
      case $? in 0) restart_headset ;; 1) again_for_speech_models ;; esac ) >/dev/null 2>&1 &
elif command -v zenity >/dev/null 2>&1; then
    ( pressed="$(zenity --question --title="Nightfall installed" --ok-label="Restart now" --cancel-label="Later" --extra-button="Speech models" --text="$SUMMARY")"
      if [ $? -eq 0 ]; then restart_headset; elif [ "$pressed" = "Speech models" ]; then again_for_speech_models; fi ) >/dev/null 2>&1 &
fi
command -v notify-send >/dev/null 2>&1 && notify-send "Nightfall build $BUILD installed" "$STEAM_MSG" >/dev/null 2>&1
