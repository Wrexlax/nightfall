//! Forwards a client's Sunshine traffic through Meteor's own ports.
//!
//! Everything is passed through untouched (HTTPS stays end-to-end between
//! the client and Sunshine, so pairing is unaffected) with one exception:
//! Sunshine's RTSP SETUP replies name the UDP ports for video, audio, and
//! control (`Transport: ...;server_port=47998`). Those are rewritten to
//! Meteor's ports so the client sends its UDP traffic here too.
//!
//! Two things are read on the way through without changing anything: the
//! client's RTSP ANNOUNCE (codec, resolution, encryption; see stream_info),
//! and the video packets, which are copied to the video tap after they have
//! been forwarded.

use std::collections::HashMap;
use std::io;
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::Mutex;

use crate::depth::{Depth, DepthFeed};
use crate::ports::{Channel, PortMap, Proto};
use crate::stream_info::{AnnounceSniffer, Codec, StreamInfo};
use crate::video_dump::VideoDump;
use crate::video_tap::{TapStats, VideoTap};

/// A UDP flow closes once neither side has sent anything for this long.
/// Sunshine itself can go quiet for much longer than this (it sends no audio
/// at all while the PC is silent), so the client's own traffic (its pings
/// every 500 ms) has to keep the flow open too. Closing the flow while the
/// client is still there loses that stream for the rest of the session:
/// Sunshine keeps sending to the closed socket, and the next ping from the
/// client goes out on a new socket Sunshine doesn't send to.
const UDP_FLOW_IDLE: Duration = Duration::from_secs(30);

type UdpFlow = (Arc<UdpSocket>, Arc<AtomicU64>, Arc<SecondLink>);

/// A second network path to a client that is already streaming (Steam Frame
/// port, "second-link").
///
/// A Steam Frame reaches the PC over the home Wi-Fi and over its wireless
/// adapter's direct link at once. Steam's own streaming sends its packets
/// over both and uses whichever copy arrives first; this does the same for
/// the picture and the sound of a stream that passes through Meteor.
///
/// How a client asks: it sends its usual video and audio pings (every
/// 500 ms) to Meteor over the second link as well. A ping is 16 bytes that
/// Sunshine made for that one stream, then a counter. Meteor has seen the
/// same 16 bytes from the address the stream runs on, so a ping carrying
/// them from another address is that client on another path: nobody else
/// knows them without already being able to read the stream. From then on
/// each packet Sunshine sends for the stream goes to both addresses. The
/// client drops whichever copy comes second.
///
/// The second link's pings stop here (the first link's keep Sunshine
/// informed), and the copies stop `SECOND_LINK_IDLE_MS` after its last ping.
///
/// A second-link ping may carry one more byte, the client's choice
/// ("second-link-only"): 0, or no byte, for both links; 1 for the second link
/// alone, which stops the packets to the first address for as long as the
/// second link keeps pinging. If it goes quiet the stream is back on the first
/// link within `SECOND_LINK_IDLE_MS`, so a second link that dies cannot leave
/// the client with nothing.
///
/// 3 ("link-hold") is 1 from a client that watches the second link itself and
/// has found it wanting: the second link first, but both links for now. A
/// ping is small enough to cross a link that can no longer carry the picture
/// (7u log: the picture gone for 4 to 10 seconds while the pings kept time),
/// so the client, which sees the picture's packets stop, is the one to say.
#[derive(Default)]
pub(crate) struct SecondLink {
    to: std::sync::Mutex<Option<Known>>,
}

/// What is known of a stream's second link.
#[derive(Clone, Copy)]
struct Known {
    addr: SocketAddr,
    /// When it last pinged (`now_ms`).
    last: u64,
    /// Whether it asked to be the only one.
    only: bool,
    /// Since when its pings have come without a late one.
    since: u64,
    /// How late a ping may be, from the pace of the last few.
    late_ms: u64,
    /// The gap before the last ping.
    gap: u64,
}

/// A second link that asked to be the only one stops being it when a ping is
/// late, and the first link carries the stream as well from then on. Late is
/// three of its pings missed: they come every 500 ms from an older client
/// (so a second and a half), and ten times a second from one that watches the
/// link while it is alone (so under half a second). Waiting out
/// `SECOND_LINK_IDLE_MS` instead froze the picture for seven seconds (7t log,
/// walking away from the adapter).
const SECOND_LINK_LATE_MS: u64 = 1_500;
const SECOND_LINK_LATE_MIN_MS: u64 = 400;

/// How late the next ping may be when the last two gaps were these.
pub(crate) fn late_after(gap: u64, gap_before: u64) -> u64 {
    (gap.max(gap_before) * 3 + 100).clamp(SECOND_LINK_LATE_MIN_MS, SECOND_LINK_LATE_MS)
}

/// Which clients have a second link, by machine address: the second address,
/// the first, and when a second-link ping last said so (`now_ms`). The pings
/// are what prove the two addresses are one client (they carry the stream's
/// own 16 bytes). The microphone and the depth server go by this to take a
/// connection from a streaming client's second address as that client's
/// ("side-both"): see `Stats::is_streaming`.
fn second_ips() -> &'static std::sync::Mutex<HashMap<IpAddr, (IpAddr, u64)>> {
    static KNOWN: std::sync::OnceLock<std::sync::Mutex<HashMap<IpAddr, (IpAddr, u64)>>> = std::sync::OnceLock::new();
    KNOWN.get_or_init(Default::default)
}

/// For this long after its last ping (twenty pings).
const SECOND_IP_FRESH_MS: u64 = 10_000;

pub(crate) fn note_second_ip(second: IpAddr, first: IpAddr, now: u64) {
    let mut known = second_ips().lock().unwrap();
    known.retain(|_, (_, seen)| now.saturating_sub(*seen) <= SECOND_IP_FRESH_MS);
    known.insert(second.to_canonical(), (first.to_canonical(), now));
}

pub(crate) fn forget_second_ip(second: IpAddr) {
    second_ips().lock().unwrap().remove(&second.to_canonical());
}

/// The first address of the client whose second address this is, if a ping
/// has said so lately.
pub(crate) fn first_ip_of(second: IpAddr, now: u64) -> Option<IpAddr> {
    let known = second_ips().lock().unwrap();
    known.get(&second.to_canonical()).filter(|(_, seen)| now.saturating_sub(*seen) <= SECOND_IP_FRESH_MS).map(|(first, _)| *first)
}

/// The streams running now, by the 16 bytes Sunshine made for each: the
/// machine address of the client it belongs to, and when a ping last carried
/// those bytes (`now_ms`). The video and audio channels fill it in from the
/// pings, over either link. It is how a control datagram that came over a
/// second link is matched to its client: see `control_trailer`.
fn stream_payloads() -> &'static std::sync::Mutex<HashMap<[u8; 16], (IpAddr, u64)>> {
    static KNOWN: std::sync::OnceLock<std::sync::Mutex<HashMap<[u8; 16], (IpAddr, u64)>>> = std::sync::OnceLock::new();
    KNOWN.get_or_init(Default::default)
}

/// A stream is known for this long after its last ping (twenty pings).
const STREAM_PAYLOAD_FRESH_MS: u64 = 10_000;

pub(crate) fn note_stream_payload(payload: [u8; 16], client: IpAddr, now: u64) {
    let mut known = stream_payloads().lock().unwrap();
    if known.len() > 64 {
        known.retain(|_, (_, seen)| now.saturating_sub(*seen) <= STREAM_PAYLOAD_FRESH_MS);
    }
    known.insert(payload, (client, now));
}

/// A stream has ended early: its 16 bytes name no client any more.
pub(crate) fn forget_stream_payload(payload: &[u8; 16]) {
    stream_payloads().lock().unwrap().remove(payload);
}

/// The payloads that `client` pinged with before `now`: the streams it ran
/// earlier from the same address and port. Once a client pings with new
/// bytes those streams are over, and their bytes must stop opening a second
/// link to it: until 0.9.0-sf12 they stayed good for as long as the flow
/// lived, so a ping from anywhere that carried a finished stream's bytes
/// was sent copies of the new one. (Upstream found the same in its own
/// multipath and fixed it in 243cfdf, 2026-11-16.)
pub(crate) fn earlier_payloads(payloads: &HashMap<[u8; 16], SocketAddr>, client: SocketAddr, now: [u8; 16]) -> Vec<[u8; 16]> {
    payloads.iter().filter(|(payload, owner)| **owner == client && **payload != now).map(|(payload, _)| *payload).collect()
}

/// The client whose stream these 16 bytes name, if a ping carried them lately.
pub(crate) fn client_of_stream(payload: &[u8; 16], now: u64) -> Option<IpAddr> {
    let known = stream_payloads().lock().unwrap();
    known.get(payload).filter(|(_, seen)| now.saturating_sub(*seen) <= STREAM_PAYLOAD_FRESH_MS).map(|(client, _)| *client)
}

/// The control channel over a client's second link too ("control-both").
///
/// The control channel is one connection (ENet) between the client and
/// Sunshine: input one way, and both ways the "are you there" that ends a
/// stream when it stops. A client with a second link sends every control
/// datagram over both, and marks the copy that goes over the second: it ends
/// with the stream's 16 bytes and then these four letters. Meteor takes the
/// mark off and passes the datagram to Sunshine out of that client's own
/// socket, so Sunshine sees one peer whose every datagram may come twice,
/// and sends Sunshine's replies to both addresses. ENet numbers its
/// datagrams and drops what it has seen, at both ends. The stream then
/// outlives either link going silent.
const CONTROL_TRAILER_MARK: &[u8; 4] = b"NFL2";

/// If `packet` is such a copy: the stream's 16 bytes, and the datagram's
/// own length without the mark.
pub(crate) fn control_trailer(packet: &[u8]) -> Option<([u8; 16], usize)> {
    let body = packet.len().checked_sub(16 + CONTROL_TRAILER_MARK.len())?;
    if body == 0 || &packet[body + 16..] != CONTROL_TRAILER_MARK {
        return None;
    }
    let mut payload = [0u8; 16];
    payload.copy_from_slice(&packet[body..body + 16]);
    Some((payload, body))
}

/// And it is the only one again once its pings have come without such a gap
/// for this long, so a link at the edge of its range doesn't flip the stream
/// back and forth. Until then both links carry it.
const SECOND_LINK_STEADY_MS: u64 = 3_000;

/// The Stream Link choice as the headset and the tray menu name it:
/// both links, the second link (the adapter) first, or the first link (Wi-Fi)
/// only. Also the first extra byte of a second-link ping.
pub const LINK_BOTH: u8 = 0;
pub const LINK_SECOND_FIRST: u8 = 1;
pub const LINK_FIRST_ONLY: u8 = 2;

/// The choice last picked, in the tray menu or on the headset, and a number
/// that goes up by one with each pick in the tray menu. The headset reads both
/// from Meteor's "are you Meteor" answer every couple of seconds and follows
/// a pick it hasn't seen; its pings carry the choice it is using and the last
/// number it saw, and once that number is the current one its choice is taken
/// as the choice. So the last change wins, whichever side made it.
pub static LINK_WANTED: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(LINK_BOTH);
pub static LINK_REV: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);
/// When a headset last said anything over its second link (`now_ms`).
pub static LINK_TOLD_MS: AtomicU64 = AtomicU64::new(0);

/// A pick in the tray menu.
pub fn pick_link(choice: u8) {
    LINK_WANTED.store(choice.min(LINK_FIRST_ONLY), Ordering::Relaxed);
    // Never 0: that number means "no pick since Meteor started".
    let next = LINK_REV.load(Ordering::Relaxed).wrapping_add(1).max(1);
    LINK_REV.store(next, Ordering::Relaxed);
}

/// The first extra byte of a ping from a client on `LINK_SECOND_FIRST` that
/// wants both links for now ("link-hold").
const PING_SECOND_FIRST_HOLD: u8 = 3;

/// What a second-link ping says about the choice.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub(crate) struct PingSays {
    /// The choice the client is using.
    pub choice: u8,
    /// The tray pick number it has seen, if it sends one.
    pub rev: Option<u8>,
    /// On `LINK_SECOND_FIRST`: both links for now, the second isn't steady.
    pub hold: bool,
}

pub(crate) fn ping_choice(packet: &[u8]) -> PingSays {
    let byte = if packet.len() > PING_LEN { packet[PING_LEN] } else { LINK_BOTH };
    let rev = if packet.len() > PING_LEN + 1 { Some(packet[PING_LEN + 1]) } else { None };
    let (choice, hold) = match byte {
        LINK_SECOND_FIRST | LINK_FIRST_ONLY => (byte, false),
        PING_SECOND_FIRST_HOLD => (LINK_SECOND_FIRST, true),
        // 0, and anything not known yet: both links, which never hurts.
        _ => (LINK_BOTH, false),
    };
    PingSays { choice, rev, hold }
}

/// The line for the tray menu: what the stream is doing about its links.
/// `told_ago` and `copy_ago` are how long ago (ms) a headset last pinged over
/// its second link and a video packet last went out over it; `None` for never.
pub fn link_status(streaming: bool, told_ago: Option<u64>, copy_ago: Option<u64>, copy_only: bool, wanted: u8) -> String {
    let recent = |ago: Option<u64>| ago.is_some_and(|ms| ms < 3_000);
    let text = if !streaming {
        "no stream"
    } else if !recent(told_ago) {
        "Wi-Fi (the headset's adapter link is not in use)"
    } else if wanted == LINK_FIRST_ONLY {
        "Wi-Fi only"
    } else if !recent(copy_ago) {
        "Wi-Fi (waiting for the adapter)"
    } else if copy_only {
        "on the adapter"
    } else if wanted == LINK_SECOND_FIRST {
        "Wi-Fi and adapter (adapter signal weak, or just back)"
    } else {
        "Wi-Fi and adapter"
    };
    format!("Stream Link: {text}")
}

/// Where a stream's packets go at one moment (`SecondLink::current`).
#[derive(Debug, PartialEq, Eq, Clone, Copy, Default)]
pub(crate) struct SecondLinkNow {
    /// The second address, while it still pings.
    pub to: Option<SocketAddr>,
    /// The second address alone: nothing goes to the first.
    pub only: bool,
    /// The address that has just gone quiet, the one time that is found out.
    pub gone_quiet: Option<SocketAddr>,
    /// It asked to be alone and isn't because a ping is late.
    pub late: bool,
}

/// Copies to a second link stop this long after its last ping (ten pings).
const SECOND_LINK_IDLE_MS: u64 = 5_000;

/// The length of a ping that carries a stream's payload: 16 bytes, then a
/// 4-byte counter. (The older ping is the four letters "PING" and names no
/// stream, so it can never open a second link.) A second-link ping may be one
/// or two bytes longer: see `ping_choice`.
const PING_LEN: usize = 20;

/// The 16 bytes that name the stream, if `packet` is such a ping.
pub(crate) fn ping_payload(packet: &[u8]) -> Option<[u8; 16]> {
    if packet.len() < PING_LEN || packet.len() > PING_LEN + 2 || packet[0] == 0 {
        return None;
    }
    let mut payload = [0u8; 16];
    payload.copy_from_slice(&packet[..16]);
    Some(payload)
}

/// Whether a second link may go to `ip` (0.9.0-sf15). Copies of a stream are
/// only ever sent to an address of the kind home networks use: the private
/// ranges, a link-local address, the range VPNs that join devices together
/// hand out (100.64.0.0/10), this PC itself, and their IPv6 counterparts.
/// The wireless adapter's link and a home Wi-Fi are always one of these. A
/// request that seems to come from anywhere else, which could only be
/// someone trying to have the picture sent out of the house, is refused.
pub(crate) fn second_link_address_ok(ip: IpAddr) -> bool {
    match ip.to_canonical() {
        IpAddr::V4(v4) => {
            let octets = v4.octets();
            v4.is_private() || v4.is_link_local() || v4.is_loopback() || (octets[0] == 100 && (octets[1] & 0xC0) == 64)
        }
        IpAddr::V6(v6) => {
            let first = v6.segments()[0];
            v6.is_loopback() || (first & 0xfe00) == 0xfc00 || (first & 0xffc0) == 0xfe80
        }
    }
}

fn refused_second_links() -> &'static std::sync::Mutex<std::collections::HashSet<IpAddr>> {
    static REFUSED: std::sync::OnceLock<std::sync::Mutex<std::collections::HashSet<IpAddr>>> = std::sync::OnceLock::new();
    REFUSED.get_or_init(Default::default)
}

/// True the first time a second link is refused for `ip`, so that the log
/// says it once and not with every ping (a flood of the same line
/// helps nobody). After 64 different addresses nothing more is said.
pub(crate) fn refused_first_time(ip: IpAddr) -> bool {
    let mut refused = refused_second_links().lock().unwrap();
    refused.len() < 64 && refused.insert(ip.to_canonical())
}

impl SecondLink {
    /// A ping came over the second link from `from`, asking for that link
    /// alone or not. True when the address or the choice is news.
    pub(crate) fn pinged(&self, from: SocketAddr, now: u64, only: bool) -> bool {
        let mut to = self.to.lock().unwrap();
        let known = (*to).filter(|k| k.addr == from);
        let news = !known.is_some_and(|k| k.only == only);
        *to = Some(match known {
            Some(k) => {
                let gap = now.saturating_sub(k.last);
                Known {
                    addr: from,
                    last: now,
                    only,
                    // A late ping starts the count of steady time again.
                    since: if gap <= k.late_ms { k.since } else { now },
                    late_ms: late_after(gap, k.gap),
                    gap,
                }
            }
            // A first ping, or a new address.
            None => Known { addr: from, last: now, only, since: now, late_ms: SECOND_LINK_LATE_MS, gap: 500 },
        });
        news
    }

    /// The client has said it wants no second link (Wi-Fi only). True when
    /// there was one.
    pub(crate) fn stop(&self) -> bool {
        self.to.lock().unwrap().take().is_some()
    }

    /// Where the stream's packets go at `now`.
    pub(crate) fn current(&self, now: u64) -> SecondLinkNow {
        let mut to = self.to.lock().unwrap();
        match *to {
            Some(k) if now.saturating_sub(k.last) <= SECOND_LINK_IDLE_MS => {
                // Alone only while its pings are on time and have been for a
                // while; otherwise the first link carries the stream too.
                let late = k.only && now.saturating_sub(k.last) > k.late_ms;
                let alone = k.only && !late && now.saturating_sub(k.since) >= SECOND_LINK_STEADY_MS;
                SecondLinkNow { to: Some(k.addr), only: alone, gone_quiet: None, late }
            }
            Some(k) => {
                *to = None;
                SecondLinkNow { to: None, only: false, gone_quiet: Some(k.addr), late: false }
            }
            None => SecondLinkNow::default(),
        }
    }
}
/// How a stream's copies leave for its second link: from a socket and a task
/// of their own, through a short queue that drops what doesn't fit.
///
/// They used to go out of the stream's own socket, one `send_to` after the
/// other. A wireless adapter whose headset has walked out of range stops
/// taking packets, the socket's send buffer fills with packets for it, and
/// the next send waits, whichever address it is for: the copies for the
/// first link (Wi-Fi) queued behind the ones for the dead adapter. Seen three
/// times in the 7v logs: from the moment the headset asked for both links,
/// nothing arrived over either for 4 to 5 seconds, Meteor's own tap of the
/// stream missed packets (225 to 435 frames incomplete with nothing dropped
/// from its queue, so the relay was not reading Sunshine), and the picture
/// came back when the second link was given up as quiet. With a socket of
/// its own the adapter can only hold up its own copies.
struct SecondLinkOut {
    name: &'static str,
    client: SocketAddr,
    queue: Option<tokio::sync::mpsc::Sender<(Vec<u8>, SocketAddr)>>,
    /// Copies that found the queue full since the last log line, and when
    /// that line was written (`now_ms`).
    dropped: u64,
    logged_ms: u64,
}

/// About a fifth of a second of a 120 Mbit/s stream, and room for the largest
/// key frame in one piece (256 was a packet short once in 14 minutes of
/// ordinary running, 7w log). More would only be delivered late, after the
/// copy over the first link.
const SECOND_LINK_QUEUE: usize = 1024;

impl SecondLinkOut {
    fn new(name: &'static str, client: SocketAddr) -> Self {
        SecondLinkOut { name, client, queue: None, dropped: 0, logged_ms: 0 }
    }

    /// Queues a copy of `packet` for `to`. False when it was dropped instead.
    fn send(&mut self, packet: &[u8], to: SocketAddr) -> bool {
        let name = self.name;
        let client = self.client;
        let queue = self.queue.get_or_insert_with(|| {
            let (queue, mut packets) = tokio::sync::mpsc::channel::<(Vec<u8>, SocketAddr)>(SECOND_LINK_QUEUE);
            tokio::spawn(async move {
                // Any free port: the client's sockets take the stream from
                // whatever port it comes, and tell the links apart by address.
                let socket = match bind_udp(0).await {
                    Ok(socket) => socket,
                    Err(err) => {
                        log::warn!("{name}: no socket for the second link of {client}: {err}");
                        return;
                    }
                };
                while let Some((packet, to)) = packets.recv().await {
                    let _ = socket.send_to(&packet, to).await;
                }
            });
            queue
        });
        if queue.try_send((packet.to_vec(), to)).is_ok() {
            return true;
        }
        self.dropped += 1;
        let now = now_ms();
        if now.saturating_sub(self.logged_ms) >= 1_000 {
            log::info!("{name}: second link for {client}: {to} isn't taking packets; copies for it dropped since the last such line: {} (the first link is not held up)",
                self.dropped);
            self.dropped = 0;
            self.logged_ms = now;
        }
        false
    }
}

const MAX_RTSP_HEADER: usize = 64 * 1024;

#[derive(Default)]
pub struct Stats {
    pub tcp_connections: AtomicUsize,
    pub udp_flows: AtomicUsize,
    pub bytes_to_client: AtomicU64,
    pub bytes_to_sunshine: AtomicU64,
    pub tap: Arc<TapStats>,
    /// Addresses with an open video flow, and how many: the clients streaming right now. A
    /// restarted stream opens its new flow before the old one idles out, so a set would forget
    /// a client that is still streaming when the old flow closes.
    /// When a video packet last went out over a client's second link (see `SecondLink`),
    /// and whether that client had asked for the second link alone. For the tray menu.
    pub second_link_ms: AtomicU64,
    pub second_link_only: std::sync::atomic::AtomicBool,
    pub video_clients: std::sync::Mutex<HashMap<IpAddr, usize>>,
    /// Actual video delivery, independent of UDP flows retained for reconnects.
    pub last_video_ms: AtomicU64,
}

impl Stats {
    /// Whether `ip` is a client with a stream running through Meteor: the
    /// address its video comes from, or that client's address on its second
    /// link (`second_ips`).
    pub fn is_streaming(&self, ip: IpAddr) -> bool {
        let first = first_ip_of(ip, now_ms());
        self.video_clients.lock().is_ok_and(|c| {
            c.contains_key(&ip.to_canonical()) || first.is_some_and(|first| c.contains_key(&first))
        })
    }

    fn set_streaming(&self, ip: IpAddr, streaming: bool) {
        if let Ok(mut clients) = self.video_clients.lock() {
            let ip = ip.to_canonical();
            if streaming {
                *clients.entry(ip).or_insert(0) += 1;
            } else if let Some(open) = clients.get_mut(&ip) {
                *open -= 1;
                if *open == 0 {
                    clients.remove(&ip);
                }
            }
        }
    }
}

#[derive(Clone)]
pub struct Proxy {
    pub map: PortMap,
    pub sunshine_host: String,
    pub stats: Arc<Stats>,
    /// From the most recent RTSP ANNOUNCE.
    pub stream: Arc<std::sync::Mutex<Option<StreamInfo>>>,
    /// `--dump-video`: write the tapped video here.
    pub dump_dir: Option<PathBuf>,
    pub depth: Option<Arc<Depth>>,
}

impl Proxy {
    pub fn new(
        map: PortMap,
        sunshine_host: String,
        stats: Arc<Stats>,
        dump_dir: Option<PathBuf>,
        depth: Option<Arc<Depth>>,
    ) -> Proxy {
        Proxy { map, sunshine_host, stats, stream: Arc::default(), dump_dir, depth }
    }

    pub async fn start(&self) -> io::Result<()> {
        for ch in crate::ports::CHANNELS {
            let port = self.map.meteor(ch);
            match ch.proto {
                Proto::Tcp => {
                    let listener = bind_tcp(port).await?;
                    tokio::spawn(self.clone().run_tcp(listener, ch));
                }
                Proto::Udp => {
                    let socket = Arc::new(bind_udp(port).await?);
                    tokio::spawn(self.clone().run_udp(socket, ch));
                }
            }
            log::info!(
                "{:>7} {:?} :{port} -> {}:{}",
                ch.name,
                ch.proto,
                self.sunshine_host,
                self.map.sunshine(ch)
            );
        }
        Ok(())
    }

    fn upstream(&self, ch: Channel) -> String {
        let host = &self.sunshine_host;
        let port = self.map.sunshine(ch);
        if host.contains(':') { format!("[{host}]:{port}") } else { format!("{host}:{port}") }
    }

    async fn run_tcp(self, listener: TcpListener, ch: Channel) {
        loop {
            let (client, peer) = match listener.accept().await {
                Ok(accepted) => accepted,
                Err(err) => {
                    log::warn!("{} accept failed: {err}", ch.name);
                    continue;
                }
            };
            let proxy = self.clone();
            tokio::spawn(async move {
                proxy.stats.tcp_connections.fetch_add(1, Ordering::Relaxed);
                if let Err(err) = proxy.forward_tcp(client, ch).await {
                    log::debug!("{} connection from {peer} ended: {err}", ch.name);
                }
                proxy.stats.tcp_connections.fetch_sub(1, Ordering::Relaxed);
            });
            log::debug!("{} connection from {peer}", ch.name);
        }
    }

    async fn forward_tcp(&self, client: TcpStream, ch: Channel) -> io::Result<()> {
        let upstream = TcpStream::connect(self.upstream(ch)).await?;
        client.set_nodelay(true)?;
        upstream.set_nodelay(true)?;
        let (mut client_rx, mut client_tx) = client.into_split();
        let (mut up_rx, mut up_tx) = upstream.into_split();
        let stats = self.stats.clone();
        let to_sunshine = async {
            let n = if ch.name == "rtsp" {
                copy_rtsp_requests(&mut client_rx, &mut up_tx, &stats.bytes_to_sunshine, &self.stream).await
            } else {
                copy_counted(&mut client_rx, &mut up_tx, &stats.bytes_to_sunshine).await
            };
            let _ = up_tx.shutdown().await;
            n
        };
        let to_client = async {
            let n = if ch.name == "rtsp" {
                copy_rtsp_replies(&mut up_rx, &mut client_tx, &self.map, &stats.bytes_to_client).await
            } else {
                copy_counted(&mut up_rx, &mut client_tx, &stats.bytes_to_client).await
            };
            let _ = client_tx.shutdown().await;
            n
        };
        let (a, b) = tokio::join!(to_sunshine, to_client);
        a.and(b).map(|_| ())
    }

    /// One upstream socket per client address, so Sunshine sees each client
    /// as a distinct peer and its replies can be routed back.
    async fn run_udp(self, listener: Arc<UdpSocket>, ch: Channel) {
        let flows: Arc<Mutex<HashMap<SocketAddr, UdpFlow>>> = Arc::default();
        // Second link: which client each stream's ping payload came from.
        let second_links = ch.name == "video" || ch.name == "audio";
        let mut payloads: HashMap<[u8; 16], SocketAddr> = HashMap::new();
        let mut buf = vec![0u8; 65536];
        loop {
            let (len, client) = match listener.recv_from(&mut buf).await {
                Ok(received) => received,
                Err(err) => {
                    // Windows reports an ICMP port-unreachable from an earlier
                    // send as a receive error; it isn't fatal.
                    log::debug!("{} receive failed: {err}", ch.name);
                    continue;
                }
            };
            let payload = if second_links { ping_payload(&buf[..len]) } else { None };
            let upstream = {
                let mut flows_guard = flows.lock().await;
                // A ping with a live stream's payload from another machine
                // address than the stream's own: that client's second link
                // (see `SecondLink`). It is noted and goes no further.
                if !flows_guard.contains_key(&client) {
                    if let Some(first) = payload.and_then(|p| payloads.get(&p).copied()) {
                        if first.ip() != client.ip() {
                            if !second_link_address_ok(client.ip()) {
                                if refused_first_time(client.ip()) {
                                    log::warn!("{}: second link for {first} refused: {} is not a home-network address, so no copy of the stream goes there (said once for this address)", ch.name, client.ip());
                                }
                                continue;
                            }
                            if let Some((_, _, second)) = flows_guard.get(&first) {
                                let says = ping_choice(&buf[..len]);
                                let choice = says.choice;
                                LINK_TOLD_MS.store(now_ms(), Ordering::Relaxed);
                                // A headset that has seen the latest pick in
                                // the tray menu is using the choice that counts.
                                if says.rev == Some(LINK_REV.load(Ordering::Relaxed)) {
                                    LINK_WANTED.store(choice, Ordering::Relaxed);
                                }
                                // Still this stream, though the first
                                // link may have gone silent.
                                if let Some(p) = payload {
                                    note_stream_payload(p, first.ip(), now_ms());
                                }
                                // For the microphone and the depth server,
                                // which go by the machine address.
                                if choice == LINK_FIRST_ONLY {
                                    forget_second_ip(client.ip());
                                } else {
                                    note_second_ip(client.ip(), first.ip(), now_ms());
                                }
                                if choice == LINK_FIRST_ONLY {
                                    if second.stop() {
                                        log::info!("{}: second link for {first}: stopped by the headset (Wi-Fi only)", ch.name);
                                    }
                                } else if second.pinged(client, now_ms(), choice == LINK_SECOND_FIRST && !says.hold) {
                                    if says.hold {
                                        log::info!("{}: second link for {first}: the headset asks for both links for now ({client} is not steady)", ch.name);
                                    } else if choice == LINK_SECOND_FIRST {
                                        log::info!("{}: second link for {first}: {client} is to carry the stream alone while it holds", ch.name);
                                    } else {
                                        log::info!("{}: second link for {first}: copies also go to {client}", ch.name);
                                    }
                                }
                                continue;
                            }
                        }
                    }
                    // A second link's ping whose stream has no flow here
                    // (yet, or any more) waits for it; it never starts one.
                    // Such a ping is known by its make: it is longer than a
                    // stream's own, by the choice it carries. Without this,
                    // whichever of a new stream's two pings arrived first
                    // owned the stream, and over the adapter's direct link
                    // that is usually the second link's: Meteor then took
                    // the adapter's address for the client's own, refused its
                    // depth and microphone (which come from the Wi-Fi
                    // address: "not a streaming client"), dropped its control
                    // copies and never heard its Stream Link choice (7x log,
                    // 2026-11-16, a stream restarted a second after it began).
                    if payload.is_some() && len > PING_LEN {
                        continue;
                    }
                }
                // A control datagram marked as a copy that came over a
                // client's second link (`control_trailer`): out of that
                // client's own socket, without the mark. It also keeps the
                // flow alive: with Wi-Fi gone silent the second link is all
                // that is left of the client. A marked datagram is never a
                // new client: one that names no stream of ours is dropped.
                if ch.name == "control" {
                    if let Some((stream, body)) = control_trailer(&buf[..len]) {
                        if !second_link_address_ok(client.ip()) {
                            if refused_first_time(client.ip()) {
                                log::warn!("control: second link refused: {} is not a home-network address, so nothing is answered there (said once for this address)", client.ip());
                            }
                            continue;
                        }
                        let flow = client_of_stream(&stream, now_ms()).and_then(|first| {
                            flows_guard
                                .iter()
                                .filter(|(addr, _)| addr.ip() == first)
                                .max_by_key(|(_, (_, last_seen, _))| last_seen.load(Ordering::Relaxed))
                                .map(|(addr, flow)| (*addr, flow.clone()))
                        });
                        drop(flows_guard);
                        if let Some((first, (socket, last_seen, second))) = flow {
                            last_seen.store(now_ms(), Ordering::Relaxed);
                            if second.pinged(client, now_ms(), false) {
                                log::info!("control: second link for {first}: taken from {client} as well, and answered there");
                            }
                            self.stats.bytes_to_sunshine.fetch_add(body as u64, Ordering::Relaxed);
                            let _ = socket.send(&buf[..body]).await;
                        }
                        continue;
                    }
                }
                match flows_guard.get(&client) {
                    Some((socket, last_seen, second)) => {
                        last_seen.store(now_ms(), Ordering::Relaxed);
                        if let Some(p) = payload {
                            // A new stream from the address and port of an
                            // earlier one: the earlier stream's bytes stop
                            // counting, and so does the second link they
                            // opened. The headset opens it again with the
                            // new stream's bytes on its next ping.
                            let earlier = earlier_payloads(&payloads, client, p);
                            if !earlier.is_empty() {
                                for gone in &earlier {
                                    payloads.remove(gone);
                                    forget_stream_payload(gone);
                                }
                                if second.stop() {
                                    log::info!("{}: second link for {client}: closed, a new stream began on this connection", ch.name);
                                }
                            }
                            payloads.insert(p, client);
                            note_stream_payload(p, client.ip(), now_ms());
                        }
                        socket.clone()
                    }
                    None => match self.open_udp_flow(ch).await {
                        Ok(socket) => {
                            let last_seen = Arc::new(AtomicU64::new(now_ms()));
                            let second = Arc::new(SecondLink::default());
                            flows_guard.insert(client, (socket.clone(), last_seen.clone(), second.clone()));
                            // Payloads of streams that have ended are let go
                            // here, when a new stream begins.
                            payloads.retain(|_, known| flows_guard.contains_key(&*known));
                            if let Some(p) = payload {
                                payloads.insert(p, client);
                                note_stream_payload(p, client.ip(), now_ms());
                            }
                            tokio::spawn(self.clone().relay_udp_replies(
                                socket.clone(),
                                listener.clone(),
                                client,
                                flows.clone(),
                                last_seen,
                                second,
                                ch,
                            ));
                            socket
                        }
                        Err(err) => {
                            log::warn!("{} flow for {client} failed: {err}", ch.name);
                            continue;
                        }
                    },
                }
            };
            if upstream.send(&buf[..len]).await.is_ok() {
                self.stats.bytes_to_sunshine.fetch_add(len as u64, Ordering::Relaxed);
            }
        }
    }

    async fn open_udp_flow(&self, ch: Channel) -> io::Result<Arc<UdpSocket>> {
        let target = tokio::net::lookup_host(self.upstream(ch))
            .await?
            .next()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "Sunshine host not found"))?;
        let local: SocketAddr = if target.is_ipv4() { "0.0.0.0:0" } else { "[::]:0" }.parse().unwrap();
        let socket = UdpSocket::bind(local).await?;
        socket.connect(target).await?;
        Ok(Arc::new(socket))
    }

    async fn relay_udp_replies(
        self,
        upstream: Arc<UdpSocket>,
        listener: Arc<UdpSocket>,
        client: SocketAddr,
        flows: Arc<Mutex<HashMap<SocketAddr, UdpFlow>>>,
        last_seen: Arc<AtomicU64>,
        second: Arc<SecondLink>,
        ch: Channel,
    ) {
        self.stats.udp_flows.fetch_add(1, Ordering::Relaxed);
        log::debug!("{} flow opened for {client}", ch.name);
        let tap = if ch.name == "video" {
            self.stats.set_streaming(client.ip(), true);
            self.start_video_tap(client, &upstream)
        } else {
            None
        };
        let mut buf = vec![0u8; 65536];
        // Whether the second link was last seen late with its pings (logged once).
        let mut was_late = false;
        let mut second_out = SecondLinkOut::new(ch.name, client);
        loop {
            match tokio::time::timeout(UDP_FLOW_IDLE, upstream.recv(&mut buf)).await {
                Ok(Ok(len)) => {
                    if ch.name == "video" && len > 0 {
                        self.stats.last_video_ms.store(crate::proxy::now_ms(), Ordering::Relaxed);
                    }
                    // Over the client's second link too, or over it alone,
                    // if it has asked (see `SecondLink`).
                    let link = second.current(now_ms());
                    if !(link.only && link.to.is_some())
                        && listener.send_to(&buf[..len], client).await.is_ok()
                    {
                        self.stats.bytes_to_client.fetch_add(len as u64, Ordering::Relaxed);
                    }
                    if let Some(addr) = link.to {
                        if second_out.send(&buf[..len], addr) && ch.name == "video" {
                            self.stats.second_link_ms.store(now_ms(), Ordering::Relaxed);
                            self.stats.second_link_only.store(link.only, Ordering::Relaxed);
                        }
                    }
                    if link.late && !was_late {
                        log::info!("{}: second link for {client}: its pings are late; packets go to {client} as well", ch.name);
                    }
                    was_late = link.late;
                    if let Some(addr) = link.gone_quiet {
                        log::info!("{}: second link for {client} went quiet ({addr}); packets go to {client} alone again", ch.name);
                    }
                    if let Some(tap) = &tap {
                        tap.push(&buf[..len]);
                    }
                }
                // Sunshine not listening yet shows up as a refused receive; keep the flow.
                Ok(Err(err)) if err.kind() == io::ErrorKind::ConnectionRefused => {}
                Ok(Err(err)) => {
                    log::debug!("{} flow for {client} failed: {err}", ch.name);
                    break;
                }
                Err(_) => {
                    // Sunshine was quiet; only close if the client is gone too.
                    let client_quiet_ms = now_ms().saturating_sub(last_seen.load(Ordering::Relaxed));
                    if client_quiet_ms >= UDP_FLOW_IDLE.as_millis() as u64 {
                        break; // idle both ways
                    }
                    log::debug!("{} flow for {client}: Sunshine quiet, client still sending; keeping it", ch.name);
                }
            }
        }
        flows.lock().await.remove(&client);
        if ch.name == "video" {
            self.stats.set_streaming(client.ip(), false);
        }
        self.stats.udp_flows.fetch_sub(1, Ordering::Relaxed);
        log::debug!("{} flow closed for {client}", ch.name);
    }

    fn start_video_tap(&self, client: SocketAddr, upstream: &UdpSocket) -> Option<VideoTap> {
        let info = self.stream.lock().ok().and_then(|s| s.clone());
        match &info {
            Some(info) if info.video_encrypted => {
                log::info!("Video for {client} is encrypted; Meteor can't read it (no host depth)");
                return None;
            }
            Some(info) if info.codec == Some(Codec::PyroWave) => {
                log::info!("Video for {client} is PyroWave; Meteor can't decode it (no host depth)");
                return None;
            }
            Some(info) => log::debug!(
                "Tapping video for {client}: {:?} {}x{} at {} fps",
                info.codec, info.width, info.height, info.fps
            ),
            None => log::debug!("Tapping video for {client} (no ANNOUNCE seen; codec from the bitstream)"),
        }
        // Loopback from Sunshine shouldn't lose packets, given room to buffer.
        enlarge_receive_buffer(upstream);
        let mut dump = self.dump_dir.clone().map(VideoDump::new);
        let mut depth = self.depth.clone().filter(|d| d.available()).map(|d| DepthFeed::new(d, Some(client.ip())));
        Some(VideoTap::start(format!("video tap {client}"), info, self.stats.tap.clone(), move |frame, codec| {
            if let Some(dump) = &mut dump {
                dump.write(frame, codec);
            }
            if let Some(depth) = &mut depth {
                depth.push(frame, codec);
            }
        }))
    }
}

pub(crate) fn now_ms() -> u64 {
    static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    START.get_or_init(std::time::Instant::now).elapsed().as_millis() as u64 + 1
}

/// Asks for an 8 MB receive buffer (the kernel may cap it at net.core.rmem_max).
fn enlarge_receive_buffer(socket: &UdpSocket) {
    let sock = socket2::SockRef::from(socket);
    let _ = sock.set_recv_buffer_size(8 * 1024 * 1024);
    if let Ok(size) = sock.recv_buffer_size() {
        log::debug!("video upstream receive buffer: {} KB", size / 1024);
    }
}

async fn bind_tcp(port: u16) -> io::Result<TcpListener> {
    match crate::net::tcp_listener(port).await {
        Ok(listener) => Ok(listener),
        Err(_) => TcpListener::bind(("0.0.0.0", port)).await,
    }
}

async fn bind_udp(port: u16) -> io::Result<UdpSocket> {
    match crate::net::udp_socket(port).await {
        Ok(socket) => Ok(socket),
        Err(_) => UdpSocket::bind(("0.0.0.0", port)).await,
    }
}

async fn copy_counted<R, W>(reader: &mut R, writer: &mut W, counter: &AtomicU64) -> io::Result<u64>
where
    R: AsyncReadExt + Unpin,
    W: AsyncWriteExt + Unpin,
{
    let mut buf = vec![0u8; 64 * 1024];
    let mut total = 0u64;
    loop {
        let n = reader.read(&mut buf).await?;
        if n == 0 {
            return Ok(total);
        }
        writer.write_all(&buf[..n]).await?;
        counter.fetch_add(n as u64, Ordering::Relaxed);
        total += n as u64;
    }
}

/// Copies the client's RTSP requests to Sunshine unchanged, noting the
/// stream settings from the ANNOUNCE.
async fn copy_rtsp_requests<R, W>(
    reader: &mut R,
    writer: &mut W,
    counter: &AtomicU64,
    stream: &std::sync::Mutex<Option<StreamInfo>>,
) -> io::Result<u64>
where
    R: AsyncReadExt + Unpin,
    W: AsyncWriteExt + Unpin,
{
    let mut sniffer = AnnounceSniffer::default();
    let mut buf = vec![0u8; 16 * 1024];
    let mut total = 0u64;
    loop {
        let n = reader.read(&mut buf).await?;
        if n == 0 {
            return Ok(total);
        }
        writer.write_all(&buf[..n]).await?;
        counter.fetch_add(n as u64, Ordering::Relaxed);
        total += n as u64;
        if let Some(info) = sniffer.feed(&buf[..n]) {
            log::info!(
                "Stream announced: {:?} {}x{} at {} fps, video {}",
                info.codec,
                info.width,
                info.height,
                info.fps,
                if info.video_encrypted { "encrypted" } else { "unencrypted" }
            );
            if let Ok(mut current) = stream.lock() {
                *current = Some(info);
            }
        }
    }
}

/// Copies Sunshine's RTSP replies to the client, rewriting the UDP ports in
/// Transport headers. Encrypted RTSP (`rtspenc://`) can't be read, so it is
/// passed through as-is and the client's UDP traffic would bypass Meteor.
async fn copy_rtsp_replies<R, W>(
    reader: &mut R,
    writer: &mut W,
    map: &PortMap,
    counter: &AtomicU64,
) -> io::Result<u64>
where
    R: AsyncReadExt + Unpin,
    W: AsyncWriteExt + Unpin,
{
    let mut pending: Vec<u8> = Vec::new();
    let mut buf = vec![0u8; 16 * 1024];
    let mut total = 0u64;
    loop {
        // Wait for a complete header block.
        let header_end = loop {
            if let Some(pos) = find(&pending, b"\r\n\r\n") {
                break Some(pos + 4);
            }
            if (!pending.is_empty() && !b"RTSP/".starts_with(&pending[..pending.len().min(5)]))
                || pending.len() > MAX_RTSP_HEADER
            {
                break None;
            }
            let n = reader.read(&mut buf).await?;
            if n == 0 {
                writer.write_all(&pending).await?;
                return Ok(total + pending.len() as u64);
            }
            pending.extend_from_slice(&buf[..n]);
        };
        let Some(header_end) = header_end else {
            log::warn!("RTSP reply isn't plain text (encrypted RTSP?); passing it through unchanged");
            writer.write_all(&pending).await?;
            counter.fetch_add(pending.len() as u64, Ordering::Relaxed);
            return Ok(total + pending.len() as u64 + copy_counted(reader, writer, counter).await?);
        };
        let header = String::from_utf8_lossy(&pending[..header_end]).into_owned();
        let rewritten = rewrite_rtsp_header(&header, map);
        let body_len = content_length(&header);
        writer.write_all(rewritten.as_bytes()).await?;
        pending.drain(..header_end);
        // Body bytes pass through untouched.
        let mut remaining = body_len;
        let from_pending = remaining.min(pending.len());
        writer.write_all(&pending[..from_pending]).await?;
        pending.drain(..from_pending);
        remaining -= from_pending;
        while remaining > 0 {
            let want = remaining.min(buf.len());
            let n = reader.read(&mut buf[..want]).await?;
            if n == 0 {
                return Ok(total);
            }
            writer.write_all(&buf[..n]).await?;
            remaining -= n;
        }
        let sent = (rewritten.len() + body_len) as u64;
        counter.fetch_add(sent, Ordering::Relaxed);
        total += sent;
    }
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn content_length(header: &str) -> usize {
    header
        .lines()
        .find_map(|line| {
            let (key, value) = line.split_once(':')?;
            key.trim().eq_ignore_ascii_case("content-length").then(|| value.trim().parse().ok())?
        })
        .unwrap_or(0)
}

pub fn rewrite_rtsp_header(header: &str, map: &PortMap) -> String {
    let mut out = String::with_capacity(header.len() + 16);
    for line in header.split_inclusive("\r\n") {
        let is_transport = line
            .split_once(':')
            .is_some_and(|(key, _)| key.trim().eq_ignore_ascii_case("transport"));
        if is_transport {
            let rewritten = rewrite_server_ports(line, map);
            if rewritten != line {
                log::info!("RTSP {} -> {}", line.trim_end(), rewritten.trim_end());
            }
            out.push_str(&rewritten);
        } else {
            out.push_str(line);
        }
    }
    out
}

/// `server_port=47998` or `server_port=47998-47999` -> Meteor's ports.
fn rewrite_server_ports(line: &str, map: &PortMap) -> String {
    const KEY: &str = "server_port=";
    let Some(start) = line.find(KEY) else { return line.to_string() };
    let value_start = start + KEY.len();
    let value_end = line[value_start..]
        .find(|c: char| !(c.is_ascii_digit() || c == '-'))
        .map_or(line.len(), |i| value_start + i);
    let ports: Vec<String> = line[value_start..value_end]
        .split('-')
        .map(|p| match p.parse::<u16>() {
            Ok(port) => map.to_meteor(port, Proto::Udp).unwrap_or(port).to_string(),
            Err(_) => p.to_string(),
        })
        .collect();
    format!("{}{}{}", &line[..value_start], ports.join("-"), &line[value_end..])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_new_stream_on_the_same_connection_retires_the_old_ones_bytes() {
        let headset: SocketAddr = "192.168.1.20:50000".parse().unwrap();
        let other: SocketAddr = "192.168.1.30:50000".parse().unwrap();
        let mut payloads: HashMap<[u8; 16], SocketAddr> = HashMap::new();
        payloads.insert([1; 16], headset);
        payloads.insert([2; 16], other);
        // The same stream pinging again retires nothing.
        assert!(earlier_payloads(&payloads, headset, [1; 16]).is_empty());
        // A new stream from the same address and port retires the old one's
        // bytes, and nobody else's.
        assert_eq!(earlier_payloads(&payloads, headset, [3; 16]), vec![[1u8; 16]]);
        // A client seen for the first time has nothing to retire.
        let new: SocketAddr = "192.168.1.40:50000".parse().unwrap();
        assert!(earlier_payloads(&payloads, new, [4; 16]).is_empty());
        // And the bytes of a retired stream name no client any more.
        note_stream_payload([9; 16], headset.ip(), 1_000);
        assert_eq!(client_of_stream(&[9; 16], 1_500), Some(headset.ip()));
        forget_stream_payload(&[9; 16]);
        assert_eq!(client_of_stream(&[9; 16], 1_500), None);
    }

    #[test]
    fn a_restarted_stream_keeps_its_client_streaming() {
        let stats = Stats::default();
        let ip: IpAddr = "10.0.0.9".parse().unwrap();
        stats.set_streaming(ip, true); // the old flow
        stats.set_streaming(ip, true); // the restarted stream's flow
        stats.set_streaming(ip, false); // the old flow idles out
        assert!(stats.is_streaming(ip), "the new flow is still open");
        stats.set_streaming(ip, false);
        assert!(!stats.is_streaming(ip));
        stats.set_streaming(ip, false); // a stray close never underflows
        assert!(!stats.is_streaming(ip));
    }

    #[test]
    fn rewrites_transport_ports() {
        let map = PortMap::new(47989, 1000).unwrap();
        let reply = "RTSP/1.0 200 OK\r\nCSeq: 3\r\nSession: DEADBEEF;timeout = 90\r\n\
                     Transport: server_port=47998\r\n\r\n";
        let out = rewrite_rtsp_header(reply, &map);
        assert!(out.contains("Transport: server_port=48998\r\n"));
        assert!(out.contains("CSeq: 3\r\n"));
        let ranged = rewrite_server_ports("Transport: unicast;server_port=48000-48001;source=x\r\n", &map);
        assert_eq!(ranged, "Transport: unicast;server_port=49000-48001;source=x\r\n");
    }

    #[test]
    fn leaves_other_headers_alone() {
        let map = PortMap::new(47989, 1000).unwrap();
        let reply = "RTSP/1.0 200 OK\r\nX-Port: server_port=47998\r\nContent-Length: 5\r\n\r\n";
        assert_eq!(rewrite_rtsp_header(reply, &map), reply);
        assert_eq!(content_length(reply), 5);
    }

    /// A fake Sunshine that echoes on its HTTP (TCP) and video (UDP) ports.
    #[test]
    fn only_a_ping_with_a_payload_names_a_stream() {
        let mut ping = [7u8; 20];
        ping[16..].copy_from_slice(&[0, 0, 0, 9]);
        assert_eq!(ping_payload(&ping), Some([7u8; 16]));
        assert_eq!(ping_payload(b"PING"), None); // the older ping
        assert_eq!(ping_payload(&[0u8; 20]), None); // no payload set
        assert_eq!(ping_payload(&[7u8; 23]), None); // not a ping: video is far longer
        // A second-link ping's extra bytes: the same stream, the choice, and
        // the tray pick the headset has seen.
        assert_eq!(ping_choice(&ping), PingSays { choice: LINK_BOTH, rev: None, hold: false });
        let mut longer = [7u8; 21];
        longer[20] = LINK_SECOND_FIRST;
        assert_eq!(ping_payload(&longer), Some([7u8; 16]));
        assert_eq!(ping_choice(&longer), PingSays { choice: LINK_SECOND_FIRST, rev: None, hold: false });
        let mut longest = [7u8; 22];
        longest[20] = LINK_FIRST_ONLY;
        longest[21] = 9;
        assert_eq!(ping_payload(&longest), Some([7u8; 16]));
        assert_eq!(ping_choice(&longest), PingSays { choice: LINK_FIRST_ONLY, rev: Some(9), hold: false });
        // 3: the second link first, but both links for now.
        longest[20] = 3;
        assert_eq!(ping_choice(&longest), PingSays { choice: LINK_SECOND_FIRST, rev: Some(9), hold: true });
        longest[20] = 200; // nonsense is read as both links, which never hurts
        assert_eq!(ping_choice(&longest).choice, LINK_BOTH);
    }

    #[test]
    fn a_second_link_lasts_while_it_pings() {
        let link = SecondLink::default();
        let addr: SocketAddr = "198.51.100.1:40000".parse().unwrap();
        let nothing = SecondLinkNow::default();
        assert_eq!(link.current(1_000), nothing);
        assert!(link.pinged(addr, 1_000, false)); // news the first time
        assert!(!link.pinged(addr, 1_500, false)); // not the second
        assert_eq!(link.current(1_500 + SECOND_LINK_IDLE_MS), SecondLinkNow { to: Some(addr), only: false, gone_quiet: None, late: false });
        // Quiet for longer: found out once, then nothing.
        assert_eq!(link.current(1_501 + SECOND_LINK_IDLE_MS), SecondLinkNow { to: None, only: false, gone_quiet: Some(addr), late: false });
        assert_eq!(link.current(1_502 + SECOND_LINK_IDLE_MS), nothing);
        assert!(link.pinged(addr, 20_000, false)); // and it can come back
        // The headset can also say stop, and that takes effect at once.
        assert!(link.stop());
        assert!(!link.stop());
        assert_eq!(link.current(20_100), nothing);
    }

    #[test]
    fn the_second_link_is_alone_only_while_it_is_steady() {
        let link = SecondLink::default();
        let addr: SocketAddr = "198.51.100.1:40000".parse().unwrap();
        let both = |link: &SecondLink, now| { let c = link.current(now); c.to == Some(addr) && !c.only };
        let alone = |link: &SecondLink, now| { let c = link.current(now); c.to == Some(addr) && c.only && !c.late };
        // Asked to be alone: both links at first, alone after three steady seconds.
        let mut now = 100_000;
        while now < 100_000 + SECOND_LINK_STEADY_MS {
            link.pinged(addr, now, true);
            assert!(both(&link, now));
            now += 500;
        }
        link.pinged(addr, now, true);
        assert!(alone(&link, now));
        assert!(alone(&link, now + SECOND_LINK_LATE_MS));
        // Its pings stop: the first link joins in after a second and a half...
        assert!(both(&link, now + SECOND_LINK_LATE_MS + 1));
        assert!(link.current(now + SECOND_LINK_LATE_MS + 1).late);
        // ...and when they come back it is not alone again at once.
        let back = now + 4_000;
        link.pinged(addr, back, true);
        assert!(both(&link, back));
        link.pinged(addr, back + 500, true);
        assert!(both(&link, back + SECOND_LINK_STEADY_MS - 1));
        let mut later = back + 1_000;
        while later <= back + SECOND_LINK_STEADY_MS {
            link.pinged(addr, later, true);
            later += 500;
        }
        assert!(alone(&link, back + SECOND_LINK_STEADY_MS));
        // Asking for both again is news, and takes effect at once.
        assert!(link.pinged(addr, later, false));
        assert!(both(&link, later));
    }

    #[test]
    fn a_link_that_pings_quickly_is_found_late_quickly() {
        // A headset that watches the link pings ten times a second while the
        // second link is alone, so three missed pings is under half a second.
        assert_eq!(late_after(500, 500), SECOND_LINK_LATE_MS);
        assert_eq!(late_after(100, 100), SECOND_LINK_LATE_MIN_MS);
        assert_eq!(late_after(100, 500), SECOND_LINK_LATE_MS); // one quick ping proves nothing
        assert_eq!(late_after(20, 20), SECOND_LINK_LATE_MIN_MS); // never twitchier than this
        let link = SecondLink::default();
        let addr: SocketAddr = "198.51.100.1:40000".parse().unwrap();
        let mut now = 200_000;
        while now <= 200_000 + SECOND_LINK_STEADY_MS + 500 {
            link.pinged(addr, now, true);
            now += 100;
        }
        let last = now - 100;
        assert!(link.current(last + SECOND_LINK_LATE_MIN_MS).only);
        let after = link.current(last + SECOND_LINK_LATE_MIN_MS + 1);
        assert!(!after.only && after.late && after.to == Some(addr));
        // Back, quickly again: both links until three steady seconds have passed.
        let back = last + 2_000;
        link.pinged(addr, back, true);
        assert!(!link.current(back + 100).only);
    }

    #[test]
    fn a_headset_that_asks_for_both_for_now_gets_both_at_once() {
        // "3" in the ping is asked of `pinged` as "not alone".
        let link = SecondLink::default();
        let addr: SocketAddr = "198.51.100.1:40000".parse().unwrap();
        let mut now = 300_000;
        while now <= 300_000 + SECOND_LINK_STEADY_MS {
            link.pinged(addr, now, true);
            now += 100;
        }
        assert!(link.current(now).only);
        assert!(link.pinged(addr, now, false)); // the hold: news
        let held = link.current(now);
        assert!(!held.only && !held.late && held.to == Some(addr));
        // In a hold the pings come twice a second again. The headset finds
        // the link steady after its three seconds; the pings never stopped,
        // so Meteor has nothing more to wait for.
        for _ in 0..7 {
            now += 500;
            link.pinged(addr, now, false);
            assert!(!link.current(now).only);
        }
        now += 100;
        assert!(link.pinged(addr, now, true));
        assert!(link.current(now).only);
    }

    #[test]
    fn a_tray_pick_has_a_number_that_is_never_zero() {
        // 0 is what a headset reads as "no pick since Meteor started".
        LINK_REV.store(254, Ordering::Relaxed);
        pick_link(LINK_FIRST_ONLY);
        assert_eq!(LINK_REV.load(Ordering::Relaxed), 255);
        pick_link(LINK_SECOND_FIRST);
        assert_eq!(LINK_REV.load(Ordering::Relaxed), 1);
        assert_eq!(LINK_WANTED.load(Ordering::Relaxed), LINK_SECOND_FIRST);
        // Anything else is taken as the nearest choice, not passed on.
        pick_link(9);
        assert_eq!(LINK_WANTED.load(Ordering::Relaxed), LINK_FIRST_ONLY);
        LINK_REV.store(0, Ordering::Relaxed);
        LINK_WANTED.store(LINK_BOTH, Ordering::Relaxed);
    }

    #[test]
    fn the_tray_line_says_what_the_stream_is_doing() {
        assert_eq!(link_status(false, None, None, false, LINK_BOTH), "Stream Link: no stream");
        assert_eq!(link_status(true, None, None, false, LINK_BOTH), "Stream Link: Wi-Fi (the headset's adapter link is not in use)");
        assert_eq!(link_status(true, Some(400), Some(10), false, LINK_BOTH), "Stream Link: Wi-Fi and adapter");
        assert_eq!(link_status(true, Some(400), Some(10), true, LINK_SECOND_FIRST), "Stream Link: on the adapter");
        assert!(link_status(true, Some(400), Some(10), false, LINK_SECOND_FIRST).contains("adapter signal weak"));
        assert_eq!(link_status(true, Some(400), Some(60_000), false, LINK_FIRST_ONLY), "Stream Link: Wi-Fi only");
        assert!(link_status(true, Some(9_000), Some(9_000), true, LINK_SECOND_FIRST).contains("not in use"));
    }

    #[test]
    fn a_control_copy_from_a_second_link_is_known_by_its_mark() {
        let stream = [b'k'; 16];
        let mut copy = vec![1u8, 2, 3, 4, 5];
        copy.extend_from_slice(&stream);
        copy.extend_from_slice(b"NFL2");
        assert_eq!(control_trailer(&copy), Some((stream, 5)));
        // An ordinary control datagram, a mark with nothing before it, and
        // one cut short are not copies.
        assert_eq!(control_trailer(&[1, 2, 3, 4, 5]), None);
        assert_eq!(control_trailer(&copy[5..]), None);
        assert_eq!(control_trailer(&copy[..copy.len() - 1]), None);
        // The stream it names has to be one whose pings are still coming.
        let client: IpAddr = "192.168.1.61".parse().unwrap();
        let other = [b'x'; 16];
        assert_eq!(client_of_stream(&other, 50_000), None);
        note_stream_payload(other, client, 50_000);
        assert_eq!(client_of_stream(&other, 50_000 + STREAM_PAYLOAD_FRESH_MS), Some(client));
        assert_eq!(client_of_stream(&other, 50_001 + STREAM_PAYLOAD_FRESH_MS), None);
    }

    #[test]
    fn a_second_link_only_goes_to_a_home_network_address() {
        let ok = |s: &str| second_link_address_ok(s.parse().unwrap());
        // Home Wi-Fi, the wireless adapter's link, a device-joining VPN, this PC.
        for address in ["192.168.1.20", "10.0.0.5", "172.16.4.9", "172.31.255.1", "169.254.10.2", "100.64.0.1", "100.127.255.254", "127.0.0.1",
            "fd12:3456::1", "fe80::1", "::1", "::ffff:192.168.1.20"] {
            assert!(ok(address), "{address} should be allowed");
        }
        // Anywhere out on the internet, however it is written.
        for address in ["8.8.8.8", "203.0.113.7", "172.32.0.1", "100.63.255.255", "100.128.0.1", "11.0.0.1", "2001:db8::1", "::ffff:8.8.8.8"] {
            assert!(!ok(address), "{address} must be refused");
        }
    }

    #[test]
    fn a_refused_second_link_is_reported_once_per_address() {
        let one: IpAddr = "203.0.113.200".parse().unwrap();
        let other: IpAddr = "203.0.113.201".parse().unwrap();
        assert!(refused_first_time(one));
        assert!(!refused_first_time(one), "said again for the same address");
        assert!(!refused_first_time("::ffff:203.0.113.200".parse().unwrap()), "the same address written the other way");
        assert!(refused_first_time(other));
        assert!(!refused_first_time(other));
    }

    #[test]
    fn a_second_address_counts_as_its_client_while_its_pings_come() {
        let first: IpAddr = "192.168.1.60".parse().unwrap();
        let second: IpAddr = "198.51.100.7".parse().unwrap();
        assert_eq!(first_ip_of(second, 70_000), None);
        note_second_ip(second, first, 70_000);
        assert_eq!(first_ip_of(second, 70_000 + SECOND_IP_FRESH_MS), Some(first));
        assert_eq!(first_ip_of(second, 70_001 + SECOND_IP_FRESH_MS), None);
        // The same address as a dual-stack socket reports it.
        let mapped: IpAddr = "::ffff:198.51.100.7".parse().unwrap();
        note_second_ip(mapped, first, 90_000);
        assert_eq!(first_ip_of(second, 90_000), Some(first));
        // "Wi-Fi only": no second link any more.
        forget_second_ip(mapped);
        assert_eq!(first_ip_of(second, 90_000), None);
    }

    #[tokio::test]
    async fn copies_for_a_second_link_never_wait() {
        // The task that sends them hasn't had a turn yet (nothing here
        // awaits), so this is a second link that takes nothing at all: the
        // queue's worth is accepted, the rest dropped, and no call waits.
        let to: SocketAddr = "127.0.0.1:9".parse().unwrap();
        let mut out = SecondLinkOut::new("video", "127.0.0.1:50000".parse().unwrap());
        let mut queued = 0;
        for _ in 0..SECOND_LINK_QUEUE + 50 {
            if out.send(&[1, 2, 3], to) {
                queued += 1;
            }
        }
        assert_eq!(queued, SECOND_LINK_QUEUE);
    }

    #[tokio::test]
    async fn forwards_tcp_and_udp_both_ways() {
        let map = PortMap::new(31989, 1000).unwrap();
        let http = PortMap::channel("http");
        let video = PortMap::channel("video");

        let tcp_echo = TcpListener::bind(("127.0.0.1", map.sunshine(http))).await.unwrap();
        tokio::spawn(async move {
            let (mut s, _) = tcp_echo.accept().await.unwrap();
            let mut buf = [0u8; 64];
            let n = s.read(&mut buf).await.unwrap();
            s.write_all(&buf[..n]).await.unwrap();
        });
        let udp_echo = UdpSocket::bind(("127.0.0.1", map.sunshine(video))).await.unwrap();
        tokio::spawn(async move {
            let mut buf = [0u8; 64];
            loop {
                let (n, from) = udp_echo.recv_from(&mut buf).await.unwrap();
                udp_echo.send_to(&buf[..n], from).await.unwrap();
            }
        });

        let stats = Arc::new(Stats::default());
        assert_eq!(stats.last_video_ms.load(Ordering::Relaxed), 0);
        let proxy = Proxy::new(map.clone(), "127.0.0.1".into(), stats.clone(), None, None);
        proxy.start().await.unwrap();

        let mut tcp = TcpStream::connect(("127.0.0.1", map.meteor(http))).await.unwrap();
        tcp.write_all(b"GET /serverinfo").await.unwrap();
        let mut buf = [0u8; 64];
        let n = tcp.read(&mut buf).await.unwrap();
        assert_eq!(&buf[..n], b"GET /serverinfo");

        let client = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        client.send_to(b"PING", ("127.0.0.1", map.meteor(video))).await.unwrap();
        let (n, from) = tokio::time::timeout(Duration::from_secs(2), client.recv_from(&mut buf))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(&buf[..n], b"PING");
        // Replies come from Meteor's port, where the client sent them.
        assert_eq!(from.port(), map.meteor(video));
        assert_eq!(stats.udp_flows.load(Ordering::Relaxed), 1);
        assert!(stats.last_video_ms.load(Ordering::Relaxed) > 0,
            "Actual video replies must wake the temporary host-cursor setting");
    }

    #[tokio::test]
    async fn rtsp_stream_rewrites_and_keeps_body() {
        let map = PortMap::new(47989, 1000).unwrap();
        let input = b"RTSP/1.0 200 OK\r\nContent-Length: 4\r\n\r\nv=0\nRTSP/1.0 200 OK\r\nTransport: server_port=47999\r\n\r\n";
        let mut reader = &input[..];
        let mut out = Vec::new();
        let counter = AtomicU64::new(0);
        copy_rtsp_replies(&mut reader, &mut out, &map, &counter).await.unwrap();
        let text = String::from_utf8(out).unwrap();
        assert_eq!(
            text,
            "RTSP/1.0 200 OK\r\nContent-Length: 4\r\n\r\nv=0\nRTSP/1.0 200 OK\r\nTransport: server_port=48999\r\n\r\n"
        );
    }
}
