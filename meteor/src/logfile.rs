//! Logs to stderr and to a file, because an autostarted AppImage has no
//! terminal: `~/.local/state/nightfall-meteor/meteor.log`, moved to
//! `meteor.log.1` when it passes 5 MB.
//!
//! Steam Frame port: the log is the file people attach to a problem report,
//! so what is written is cleaned first ([`masked`]): network addresses keep
//! only their last part (enough to tell the headset's two links apart),
//! hardware addresses are blanked, and the name in a home-folder path is
//! replaced by `~`.

use std::borrow::Cow;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::net::{Ipv4Addr, Ipv6Addr};
use std::path::{Path, PathBuf};

const MAX_BYTES: u64 = 5_000_000;

pub fn path() -> PathBuf {
    if cfg!(windows) {
        return crate::config::cache_dir().join("meteor.log");
    }
    if cfg!(target_os = "macos") {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
        return home.join("Library/Logs/Nightfall Meteor/meteor.log");
    }
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .unwrap_or_default();
    base.join("nightfall-meteor").join("meteor.log")
}

/// Starts logging (RUST_LOG, default info). `rotate` is for the main
/// process; the engine-build child only appends.
pub fn init(rotate: bool) {
    let mut builder = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"));
    // The tray's D-Bus calls, one per menu refresh, aren't worth a log line.
    builder.filter_module("tracing::span", log::LevelFilter::Off).filter_module("zbus", log::LevelFilter::Warn);
    if let Some(tee) = Tee::open(path(), rotate) {
        builder.target(env_logger::Target::Pipe(Box::new(tee)));
    }
    builder.init();
}

/// Writes each record to stderr and the log file.
struct Tee {
    path: PathBuf,
    file: File,
    written: u64,
    rotate: bool,
}

impl Tee {
    fn open(path: PathBuf, rotate: bool) -> Option<Tee> {
        std::fs::create_dir_all(path.parent()?).ok()?;
        let size = std::fs::metadata(&path).map_or(0, |m| m.len());
        if rotate && size > MAX_BYTES {
            let _ = std::fs::rename(&path, backup(&path));
        }
        let file = OpenOptions::new().create(true).append(true).open(&path).ok()?;
        let written = file.metadata().map_or(0, |m| m.len());
        Some(Tee { path, file, written, rotate })
    }
}

fn backup(path: &Path) -> PathBuf {
    path.with_extension("log.1")
}

impl Write for Tee {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        // Counted as written whole, whatever its cleaned length.
        let asked = buf.len();
        let text = String::from_utf8_lossy(buf);
        let cleaned = masked(&text);
        let buf = cleaned.as_bytes();
        let _ = std::io::stderr().write_all(buf);
        if self.rotate && self.written > MAX_BYTES {
            let _ = std::fs::rename(&self.path, backup(&self.path));
            if let Ok(file) = OpenOptions::new().create(true).append(true).open(&self.path) {
                self.file = file;
                self.written = 0;
            }
        }
        // A full disk mustn't stop Meteor: the file is best effort.
        if self.file.write_all(buf).is_ok() {
            self.written += buf.len() as u64;
        }
        Ok(asked)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        let _ = std::io::stderr().flush();
        let _ = self.file.flush();
        Ok(())
    }
}

fn word(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// The text with what identifies a network or a person taken out.
/// - IPv4: `192.168.1.50` becomes `x.x.x.50`. Loopback and `0.0.0.0` stay.
///   Four numbers after a letter, `-`, `_` or `.` are a version, not an
///   address, and stay (`libs-10.16.1.11`).
/// - IPv6: `fe80::1c2:9a4f` becomes `x::9a4f`. `::1` and `::` stay, and so
///   does the `::ffff:` in front of an IPv4 address.
/// - Hardware addresses (`aa:bb:cc:dd:ee:ff`, `aa-bb-...`) become `xx:xx`.
/// - `C:\Users\name\`, `/home/name/` and `/Users/name/` lose the name.
pub fn masked(text: &str) -> Cow<'_, str> {
    if !text.bytes().any(|b| b == b'.' || b == b':' || b == b'\\' || b == b'/' || b == b'-') {
        return Cow::Borrowed(text);
    }
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    let mut changed = false;
    while i < chars.len() {
        let before = if i == 0 { None } else { Some(chars[i - 1]) };
        // Where a path or an address can begin: not inside a word, and not
        // inside something joined by colons (a Rust path, a clock time).
        let begins = before.is_none_or(|c| !word(c) && c != ':');
        if begins && let Some((len, replacement)) = home_name(&chars[i..]) {
            out.push_str(&replacement);
            i += len;
            changed = true;
            continue;
        }
        if !begins || !(chars[i].is_ascii_hexdigit() || chars[i] == ':') {
            out.push(chars[i]);
            i += 1;
            continue;
        }
        // "libs-10.16.1.11" and "a.10.16.1.11" are versions.
        let version_like = match before {
            Some('.') => true,
            Some('-') => i >= 2 && (chars[i - 2].is_ascii_alphabetic() || chars[i - 2] == '_'),
            _ => false,
        };
        if !version_like && let Some(len) = dashed_hardware_address(&chars[i..]) {
            out.push_str("xx:xx");
            i += len;
            changed = true;
            continue;
        }
        // The longest run that could be an address, without the sentence's
        // own punctuation at its end ("from 10.0.0.5.").
        let mut end = i;
        while end < chars.len() && (chars[end].is_ascii_hexdigit() || matches!(chars[end], ':' | '.')) {
            end += 1;
        }
        while end > i && matches!(chars[end - 1], '.' | ':') {
            end -= 1;
        }
        if end == i {
            out.push(chars[i]);
            i += 1;
            continue;
        }
        let run: String = chars[i..end].iter().collect();
        let ends = chars.get(end).is_none_or(|c| !word(*c));
        let replacement = if version_like || !ends { None } else { with_ipv4_inside(&run).or_else(|| address(&run)) };
        match replacement {
            Some(replacement) => {
                changed |= replacement != run;
                out.push_str(&replacement);
            }
            None => out.push_str(&run),
        }
        i = end;
    }
    if changed { Cow::Owned(out) } else { Cow::Borrowed(text) }
}

/// `aa-bb-cc-dd-ee-ff` at the start of `chars`: its length.
fn dashed_hardware_address(chars: &[char]) -> Option<usize> {
    if chars.len() < 17 || chars.get(17).is_some_and(|c| word(*c) || *c == '-') {
        return None;
    }
    let fits = chars[..17].iter().enumerate().all(|(n, c)| if n % 3 == 2 { *c == '-' } else { c.is_ascii_hexdigit() });
    fits.then_some(17)
}

/// What a whole run is written as, if it is an address.
fn address(run: &str) -> Option<String> {
    if let Ok(v4) = run.parse::<Ipv4Addr>() {
        return Some(if v4.is_loopback() || v4.is_unspecified() { run.to_string() } else { format!("x.x.x.{}", v4.octets()[3]) });
    }
    // aa:bb:cc:dd:ee:ff.
    let parts: Vec<&str> = run.split(':').collect();
    if parts.len() == 6 && parts.iter().all(|p| p.len() == 2 && p.bytes().all(|b| b.is_ascii_hexdigit())) {
        return Some("xx:xx".into());
    }
    if run.contains("::") || run.matches(':').count() == 7 {
        if let Ok(v6) = run.parse::<Ipv6Addr>() {
            if v6.is_loopback() || v6.is_unspecified() {
                return Some(run.to_string());
            }
            return Some(format!("x::{:x}", v6.segments()[7]));
        }
    }
    None
}

/// `::ffff:192.168.1.50`, `192.168.1.50:47989` and the two together.
fn with_ipv4_inside(run: &str) -> Option<String> {
    let (head, rest) = match run.strip_prefix("::ffff:") {
        Some(rest) => ("::ffff:", rest),
        None => ("", run),
    };
    let (host, port) = match rest.rsplit_once(':') {
        Some((host, port)) if !port.is_empty() && port.bytes().all(|b| b.is_ascii_digit()) => (host, Some(port)),
        _ => (rest, None),
    };
    if head.is_empty() && port.is_none() {
        return None;
    }
    let v4 = host.parse::<Ipv4Addr>().ok()?;
    let shown = if v4.is_loopback() || v4.is_unspecified() { host.to_string() } else { format!("x.x.x.{}", v4.octets()[3]) };
    Some(match port {
        Some(port) => format!("{head}{shown}:{port}"),
        None => format!("{head}{shown}"),
    })
}

/// A home-folder path at the start of `chars`: how many characters the
/// prefix and the name take, and what to write for them.
fn home_name(chars: &[char]) -> Option<(usize, String)> {
    let text: String = chars.iter().take(80).collect();
    for (prefix, separator) in [("\\Users\\", '\\'), ("/home/", '/'), ("/Users/", '/')] {
        // Windows: a drive letter and a colon come first.
        let start = if separator == '\\' {
            let mut letters = text.chars();
            match (letters.next(), letters.next()) {
                (Some(drive), Some(':')) if drive.is_ascii_alphabetic() => 2,
                _ => continue,
            }
        } else {
            0
        };
        let Some(rest) = text[start..].strip_prefix(prefix) else { continue };
        // A Windows account name can hold spaces; the others can't.
        let name_len = rest.chars().take_while(|c| *c != separator && *c != '"' && *c != '\n' && (separator == '\\' || !c.is_whitespace())).count();
        if name_len == 0 || name_len > 40 || rest.chars().nth(name_len) != Some(separator) {
            continue;
        }
        let taken = start + prefix.chars().count() + name_len;
        return Some((taken, format!("{}{prefix}~", &text[..start])));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::{Tee, masked};
    use std::io::Write;

    #[test]
    fn the_file_gets_the_cleaned_text() {
        let dir = std::env::temp_dir().join(format!("nf-logfile-{}", std::process::id()));
        let path = dir.join("meteor.log");
        let mut tee = Tee::open(path.clone(), true).unwrap();
        let line = b"[t INFO x] Depth client [::ffff:192.168.1.50]:34132 connected\n";
        // The caller is told its whole record was taken, whatever was written.
        assert_eq!(tee.write(line).unwrap(), line.len());
        tee.flush().unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "[t INFO x] Depth client [::ffff:x.x.x.50]:34132 connected\n");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn addresses_keep_only_their_last_part() {
        assert_eq!(masked("Depth connection from [::ffff:192.168.1.50]:34132 refused"), "Depth connection from [::ffff:x.x.x.50]:34132 refused");
        assert_eq!(masked("proxying Sunshine at 192.168.1.50 (settings"), "proxying Sunshine at x.x.x.50 (settings");
        assert_eq!(masked("https Tcp :50984 -> 10.0.0.23:49984"), "https Tcp :50984 -> x.x.x.23:49984");
        assert_eq!(masked("second link for 192.168.1.60:45395: taken from 10.0.0.1:45395 as well."), "second link for x.x.x.60:45395: taken from x.x.x.1:45395 as well.");
        assert_eq!(masked("from 10.0.0.5."), "from x.x.x.5.");
        assert_eq!(masked("peer fe80::1c2:9a4f answered"), "peer x::9a4f answered");
        assert_eq!(masked("[2001:db8:0:1:2:3:4:5]:443"), "[x::5]:443");
        assert_eq!(masked("adapter 02:00:00:aa:0f:11 and 02-00-00-AA-0F-11"), "adapter xx:xx and xx:xx");
    }

    #[test]
    fn what_is_not_an_address_is_left_alone() {
        for line in [
            "[2026-01-01T12:34:56Z INFO  nightfall_meteor::host::view] Bundled host: Running",
            "rtsp://127.0.0.1:50010 -> rtsp://127.0.0.1:51010",
            "listening on 0.0.0.0:49900 and [::]:49900, [::1]:47989",
            "tensorrt_cu13_libs-10.16.1.11-py3-none-win_amd64.whl",
            "runtime\\tensorrt-10.16.1\\nvinfer_10.dll",
            "vda_s_518x294-0982c66a3ec3-fp16-opt4-trt10.16.1-sm120-nvidia-geforce-rtx-5090",
            "ncnn 1.0.20260526, NVIDIA GeForce RTX 5090",
            "prepare 0.24/0.29 ms; model 2.52/2.86 ms; 142.3 steps/s",
            "Nightfall Meteor 0.9.0-sf16 on base port 49989",
            "nightfall_meteor::depth_server] depth TCP :49901",
            "nightfall_meteor::add::dead::beef] cafe",
            "control Udp :50999",
            "at 12:34:56 and 1920x1080@144",
            "version 1.2.3.4a and v1.2.3.4",
        ] {
            assert_eq!(masked(line), line);
        }
    }

    #[test]
    fn a_home_folder_loses_its_name() {
        assert_eq!(
            masked("(settings: C:\\Users\\Some One\\AppData\\Roaming\\Nightfall Meteor\\meteor.toml)"),
            "(settings: C:\\Users\\~\\AppData\\Roaming\\Nightfall Meteor\\meteor.toml)"
        );
        assert_eq!(masked("Log: /home/deck/.local/state/nightfall-meteor/meteor.log"), "Log: /home/~/.local/state/nightfall-meteor/meteor.log");
        assert_eq!(masked("/Users/alex/Library/Logs/x"), "/Users/~/Library/Logs/x");
        assert_eq!(masked("C:\\Users\\Public"), "C:\\Users\\Public");
        assert_eq!(masked("see /home/ for more"), "see /home/ for more");
    }
}
