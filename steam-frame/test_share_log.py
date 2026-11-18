#!/usr/bin/env python3
"""Checks for package/share_log.py, the cleaner that masks addresses, ids and
names in the log copy meant for sharing: what must be masked, and what must
be left alone.   Run:  python3 steam-frame/test_share_log.py"""
import importlib.util, os, sys
sys.dont_write_bytecode = True   # no __pycache__ in package/: the whole folder is shipped
spec = importlib.util.spec_from_file_location("share_log", os.path.join(os.path.dirname(os.path.abspath(__file__)), "package", "share_log.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
c = m.Cleaner(home="/home/steamos")
masked = [
    (b"[2026-01-01 12:00:00] Received broadcast message from client 1234567890123456789 (EXAMPLE-PC): 192.168.1.50:27036",
     b"[2026-01-01 12:00:00] Received broadcast message from client <id> (<name>): x.x.x.50:27036"),
    (b"Received broadcast message from client 1234567890123456789: 1234567890123456789:27036",
     b"Received broadcast message from client <id> (<name>): <id>:27036"),
    (b"[PAIR] Starting pair with 192.168.1.50:49989...", b"[PAIR] Starting pair with x.x.x.50:49989..."),
    (b"connected to 10.0.0.13.", b"connected to x.x.x.13."),
    (b"GET https://192.168.1.50:49984/polaris/v1/display/manifest?uniqueid=0123ABCD4567EF89&uuid=1b2c3d4e-aaaa-bbbb-cccc-1234567890ab&outputs=",
     b"GET https://x.x.x.50:49984/polaris/v1/display/manifest?uniqueid=<id>&uuid=<id>&outputs="),
    (b"[mDNS] Discovered: ip='192.168.1.50' friendly='MY-PC' port=47989", b"[mDNS] Discovered: ip='x.x.x.50' friendly=<name> port=47989"),
    (b'{"hostname": "MY-PC", "server_unique_id": "AABBCCDD11223344"}', b'{"hostname": <name>, "server_unique_id": <id>}'),
    (b"[WOL] Sending WoL to 02:00:00:aa:bb:cc via 192.168.1.50", b"[WOL] Sending WoL to xx:xx:xx:xx:xx:xx via x.x.x.50"),
    (b"usb link fe80::1234:56ff:fe78:9abc%usb0 up", b"usb link <ipv6-address> up"),
    (b"pair http://[fe80::1%usb0]:47989/pair", b"pair http://<ipv6-address>:47989/pair"),
    (b"host [2001:db8::17]:47989", b"host <ipv6-address>:47989"),
    (b"speech model not installed (/home/steamos/.local/share/nightfall/whisper/ggml-base.en.bin)", b"speech model not installed (~/.local/share/nightfall/whisper/ggml-base.en.bin)"),
    (b"path /home/dan/Games and C:\\Users\\Dan\\Downloads", b"path /home/<user>/Games and C:\\Users\\<user>\\Downloads"),
    (b"pairing PIN: 4821 shown", b"pairing PIN: <removed> shown"),
    (b"rikey=00112233445566778899aabbccddeeff rikeyid=12345678", b"rikey=<id> rikeyid=<id>"),
    (b"account dan.k@example.com id 76561198000000001 [U:1:12345678]", b"account <e-mail> id <steam-id> [U:1:<steam-id>]"),
    (b"AccountName: dank77 persona_name='Dan'", b"AccountName: <name> persona_name=<name>"),
    (b"cert -----BEGIN CERTIFICATE-----MIIC...-----END CERTIFICATE----- ok", b"cert <certificate or key removed> ok"),
    (b"controller serial_number: LHR-1A2B3C4D", b"controller serial_number: <serial>"),
]
same = [
    b"[REFRESH] Runtime rates=[144.0] current=144Hz target=144Hz",
    b"[2026-01-01 12:00:00] [STATS] app=144.0fps video_update=72.0fps",
    b"== 2026-01-01T12:00:00+00:00 launching Nightfall.arm64 (SteamAppId=1234567890)",
    b"listening on 127.0.0.1:47950 and 0.0.0.0:0",
    b"Godot Engine v4.7.stable.official.5b4e0cb0f",
    b"GfeVersion 3.23.0.74 appversion 7.1.431.-1",
    b"Mesa version 25.3.0.1 (turnip)",
    b"[12:34:56] frame parts: xrBeginFrame 0.09 ms",
    b"centres (0.165, 0.105) (-0.151, 0.124) scale 1.2.3.4.5",
    b"A PIN appears here once the PC asks for it.",
    b"res=1920x1080@144 bitrate 30Mbps host_id=1 app_id=1234567890",
    b"Device Ignored -- Vendor: 0x0e6f Product: 0x0165",
    b"hex 00:11:22:33:44:55:66:77 dump",
]
bad = 0
for before, want in masked:
    got = c.line(before)
    if got != want:
        bad += 1; print("MASK  ", before, "\n   got ", got, "\n   want", want)
for line in same:
    got = c.line(line)
    if got != line:
        bad += 1; print("ALTERED", line, "\n   got ", got)
# A certificate over several lines disappears, and cleaning goes on after it.
c2 = m.Cleaner(home="/home/steamos")
out = c2.lines(b"a 192.168.1.5\n-----BEGIN PRIVATE KEY-----\nMIIabc\ndef\n-----END PRIVATE KEY-----\nb 192.168.1.6\n")
if out != b"a x.x.x.5\n<certificate or key removed>\nb x.x.x.6\n":
    bad += 1; print("CERT", out)
print("%d masked cases, %d left-alone cases, %d wrong" % (len(masked), len(same), bad))
sys.exit(1 if bad else 0)
