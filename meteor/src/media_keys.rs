//! Media keys pressed on the PC for a streaming headset (Steam Frame port,
//! 0.9.0-sf13).
//!
//! Nightfall's keyboard has volume, mute and playback keys. Sent down the
//! stream like any other key they arrive in Windows as letters (build 8h on
//! the headset: Mute typed "d", Play "g"): the streaming host turns every key
//! into a scan code and marks only a fixed list as "extended", and a media
//! key's scan code without that mark is a letter key's (Vibepollo and
//! Sunshine, `src/platform/windows/input.cpp`, `keyboard_update`). Meteor
//! runs in the user's own session, so it presses the key itself, by its
//! virtual-key code, which is how Windows' own on-screen controls do it.
//!
//! Asked for over discovery's HTTP port (`/meteor/media?key=...`), and only
//! by an address that has a stream running through Meteor. The answer, and
//! the page a streaming headset reads every couple of seconds
//! (`/meteor/link`), say whether Windows is muted (`muted`).

/// The keys a headset may ask for, by the name in its request, with the
/// Windows virtual-key code each stands for. Nothing else can be pressed
/// through this door.
const KEYS: [(&str, u8); 7] = [
    ("mute", 0xAD),
    ("volume-down", 0xAE),
    ("volume-up", 0xAF),
    ("next", 0xB0),
    ("previous", 0xB1),
    ("stop", 0xB2),
    ("play-pause", 0xB3),
];

/// The virtual-key code for a name from a request, if it is one of ours.
pub fn code(name: &str) -> Option<u8> {
    KEYS.iter().find(|(known, _)| *known == name).map(|(_, code)| *code)
}

/// The key name in a request path such as `/meteor/media?key=mute`; `None`
/// for any other path.
pub fn name_in(path: &str) -> Option<&str> {
    path.strip_prefix("/meteor/media?key=")
}

/// Whether this build can press them (the discovery answer says so with
/// "media-keys", and a headset only shows the keys to a Meteor that does).
pub const SUPPORTED: bool = cfg!(windows);

/// Presses and lets go of one media key. `Err` says why not, in words fit
/// for the log.
pub fn press(name: &str) -> Result<(), &'static str> {
    let Some(code) = code(name) else { return Err("not a media key") };
    tap(code)
}

#[cfg(windows)]
fn tap(code: u8) -> Result<(), &'static str> {
    // keybd_event (user32): the key by its virtual-key code, down then up.
    // Declared here so that Cargo.toml needs no further windows-sys feature.
    #[link(name = "user32")]
    unsafe extern "system" {
        fn keybd_event(vk: u8, scan: u8, flags: u32, extra_info: usize);
    }
    const KEYEVENTF_EXTENDEDKEY: u32 = 0x0001;
    const KEYEVENTF_KEYUP: u32 = 0x0002;
    // SAFETY: keybd_event takes four plain values and keeps nothing.
    unsafe {
        keybd_event(code, 0, KEYEVENTF_EXTENDEDKEY, 0);
        keybd_event(code, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, 0);
    }
    Ok(())
}

#[cfg(not(windows))]
fn tap(_code: u8) -> Result<(), &'static str> {
    Err("media keys are only pressed on Windows")
}

/// Whether Windows' default output is muted right now, so that the
/// headset's Mute key can show it (0.9.0-sf14); `None` where it can't be
/// told. Asks Windows' audio endpoint each time: the PC's own keys and
/// mixer change it too. Call it from a thread that may block for a moment
/// (it sets COM up for the call and takes it down again).
#[cfg(windows)]
pub fn muted() -> Option<bool> {
    use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
    use windows::Win32::Media::Audio::{IMMDeviceEnumerator, MMDeviceEnumerator, eConsole, eRender};
    use windows::Win32::System::Com::{CLSCTX_ALL, CoCreateInstance};
    if wasapi::initialize_mta().is_err() {
        return None;
    }
    // The interfaces are let go at the end of this closure, before COM is
    // taken down for the thread.
    let answer = (|| {
        // SAFETY: plain COM calls on interfaces this closure owns.
        unsafe {
            let enumerator: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL).ok()?;
            let device = enumerator.GetDefaultAudioEndpoint(eRender, eConsole).ok()?;
            let volume = device.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None).ok()?;
            Some(volume.GetMute().ok()?.as_bool())
        }
    })();
    wasapi::deinitialize();
    answer
}

#[cfg(not(windows))]
pub fn muted() -> Option<bool> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_seven_media_keys_have_a_code() {
        assert_eq!(code("mute"), Some(0xAD));
        assert_eq!(code("volume-down"), Some(0xAE));
        assert_eq!(code("volume-up"), Some(0xAF));
        assert_eq!(code("next"), Some(0xB0));
        assert_eq!(code("previous"), Some(0xB1));
        assert_eq!(code("stop"), Some(0xB2));
        assert_eq!(code("play-pause"), Some(0xB3));
        for other in ["", "Mute", "mute ", "win", "enter", "0xAD", "173", "mute&key=enter"] {
            assert_eq!(code(other), None, "{other:?} must not be pressable");
        }
        assert!(press("delete").is_err());
    }

    #[test]
    fn the_name_is_read_from_the_media_path_only() {
        assert_eq!(name_in("/meteor/media?key=mute"), Some("mute"));
        assert_eq!(name_in("/meteor/media?key="), Some(""));
        assert_eq!(name_in("/meteor/media"), None);
        assert_eq!(name_in("/meteor/link"), None);
        assert_eq!(name_in("/meteor?key=mute"), None);
    }
}
