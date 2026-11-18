#!/usr/bin/env python3
"""Makes a copy of a log that is fit to send to someone else.

Nightfall's own logs stay as they are on the headset (they are for finding
faults, and nobody else reads them there). The copy in
~/Downloads/Nightfall-logs/ is the one that gets attached to messages and
posted on forums, so that copy is made through this cleaner:

  network addresses     192.168.1.50 -> x.x.x.50 (the last number stays, so two
                        machines can still be told apart); IPv6 and hardware
                        (MAC) addresses are replaced whole
  device and pairing    the ids the headset and a PC give each other, session
  ids, keys, PINs       keys, pairing PINs, certificates
  names                 a PC's name, a network's name, the home folder's
                        user name, e-mail addresses, Steam account numbers

  share_log.py follow <log> <copy>   run beside Nightfall: every 20 seconds the
                                     log's new lines are cleaned and added to
                                     the copy; a last time when told to stop
  share_log.py clean <in> <out>      clean one file once ("-" for stdin/stdout)

Works on bytes, a line at a time: a log can hold anything.
"""
import os
import re
import signal
import sys
import time

FOLLOW_SECONDS = 20
HEADER = (b"# Cleaned for sharing: network addresses, device ids, keys and names are masked.\n"
          b"# The untouched log stays on the headset (WHERE-THINGS-ARE.txt says where).\n")

_VALUE = rb"""('[^'\n]*'|"[^"\n]*"|[^\s&,;)\]}'"]+)"""
_SEP = rb"""((?:\\?["'])?\s*[=:]\s*)"""

# Each rule: what it finds, and what goes in its place.
_ID = re.compile(rb"(?i)\b((?:server_?)?unique_?id|uuid|rikey(?:id)?|client_?id|device_?id|session_?id)\b" + _SEP + _VALUE)
_SECRET = re.compile(rb"(?i)\b(pin|password|passwd|secret|token|api_?key|auth(?:orization)?)\b" + _SEP + _VALUE)
_NAME = re.compile(rb"(?i)\b(friendly(?:_?name)?|host_?name|computer_?name|pc_?name|user_?name|account_?name|persona_?name|ssid)\b" + _SEP + _VALUE)
_SERIAL = re.compile(rb"(?i)\b(serial(?:_?number| number)?)\b" + _SEP + _VALUE)
_MAC = re.compile(rb"(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:])")
_IPV6 = re.compile(rb"(?i)\bfe80:[0-9a-f:]*(?:%[\w.-]+)?|\[[0-9a-f]{0,4}(?::[0-9a-f]{0,4}){2,7}(?:%[\w.-]+)?\]")
# Four numbers with dots, and not part of a longer run of them.
_IPV4 = re.compile(rb"(?<!\d)(?<!\d\.)(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?!\d|\.\d|-\d)")
_EMAIL = re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]+")
_STEAM_ID = re.compile(rb"\b7656119\d{10}\b|(?<=\[U:1:)\d+(?=\])")
_HOME_USER = re.compile(rb"(/home/|/Users/|[A-Za-z]:\\Users\\)[^/\\\s\"']+")
# Steam's own logs (collect-steamos-logs.sh) name other devices on the
# network by their Steam name and a long number:
# "... from client 1234567890123456789 (EXAMPLE-PC): ...".
_STEAM_PEER = re.compile(rb"(?i)\b(client|device|machine) (\d{9,})(?: \([^)\n]{1,64}\))?")
_CERT_BEGIN = re.compile(rb"-----BEGIN [A-Z ]+-----")
_CERT_END = re.compile(rb"-----END [A-Z ]+-----")


def _ipv4(match):
    parts = [int(p) for p in match.groups()]
    if any(p > 255 for p in parts):
        return match.group(0)
    # This machine itself, "any address" and "everyone": no one's address.
    if parts[0] == 127 or parts == [0, 0, 0, 0] or parts == [255, 255, 255, 255]:
        return match.group(0)
    # A version number that happens to have four parts.
    before = match.string[max(0, match.start() - 24):match.start()].lower()
    if b"version" in before or before.rstrip().endswith((b"v", b"ver")):
        return match.group(0)
    return b"x.x.x." + match.group(4)


def _ipv6(match):
    text = match.group(0)
    # "[12:34:56]" is a time of day: an address in brackets has letters or "::".
    if text.startswith(b"[") and b"::" not in text and not re.search(rb"(?i)[a-f]", text):
        return text
    return b"<ipv6-address>"


class Cleaner:
    """Cleans a log a line at a time (a certificate runs over several)."""

    def __init__(self, home=None):
        home = os.path.expanduser("~") if home is None else home
        self._home = home.encode() if len(home) > 1 else None
        self._in_certificate = False

    def line(self, text):
        """One line without its line end -> the cleaned line, or None to drop it."""
        if self._in_certificate:
            if _CERT_END.search(text):
                self._in_certificate = False
            return None
        begin = _CERT_BEGIN.search(text)
        if begin:
            end = _CERT_END.search(text, begin.end())
            if not end:
                self._in_certificate = True
                return text[:begin.start()] + b"<certificate or key removed>"
            text = text[:begin.start()] + b"<certificate or key removed>" + text[end.end():]
        if self._home:
            text = text.replace(self._home, b"~")
        text = _HOME_USER.sub(rb"\1<user>", text)
        text = _ID.sub(rb"\1\2<id>", text)
        text = _SECRET.sub(rb"\1\2<removed>", text)
        text = _NAME.sub(rb"\1\2<name>", text)
        text = _SERIAL.sub(rb"\1\2<serial>", text)
        text = _MAC.sub(b"xx:xx:xx:xx:xx:xx", text)
        text = _IPV6.sub(_ipv6, text)
        text = _IPV4.sub(_ipv4, text)
        text = _EMAIL.sub(b"<e-mail>", text)
        text = _STEAM_ID.sub(b"<steam-id>", text)
        # The same number often follows once more on the line.
        for number in {match.group(2) for match in _STEAM_PEER.finditer(text)}:
            text = _STEAM_PEER.sub(rb"\1 <id> (<name>)", text).replace(number, b"<id>")
        return text

    def lines(self, data):
        """Whole lines (each ending in a line break) -> their cleaned bytes."""
        out = []
        for raw in data.split(b"\n")[:-1]:
            cleaned = self.line(raw)
            if cleaned is not None:
                out.append(cleaned)
        return b"\n".join(out) + (b"\n" if out else b"")


def clean_file(source, target):
    cleaner = Cleaner()
    data = sys.stdin.buffer.read() if source == "-" else open(source, "rb").read()
    if not data.endswith(b"\n"):
        data += b"\n"
    out = HEADER + cleaner.lines(data)
    if target == "-":
        sys.stdout.buffer.write(out)
    else:
        with open(target, "wb") as f:
            f.write(out)


def follow(source, target, seconds=FOLLOW_SECONDS):
    """Keeps `target` as the cleaned copy of the growing `source` until told to stop."""
    stop = {"now": False}

    def _stop(*_):
        stop["now"] = True
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    cleaner = Cleaner()
    with open(target, "wb") as f:
        f.write(HEADER)
    offset = 0
    rest = b""   # the part of a line that has been read before its end arrived

    def add(final=False):
        nonlocal offset, rest
        try:
            with open(source, "rb") as f:
                f.seek(offset)
                data = f.read()
        except OSError:
            return
        offset += len(data)
        data = rest + data
        cut = data.rfind(b"\n") + 1
        whole, rest = data[:cut], data[cut:]
        if final and rest:
            whole, rest = whole + rest + b"\n", b""
        if whole:
            # Opened only for the write: an upload can't take a file that
            # something still has open.
            with open(target, "ab") as f:
                f.write(cleaner.lines(whole))

    waited = 0.0
    while not stop["now"]:
        time.sleep(0.5)
        waited += 0.5
        if waited >= seconds:
            waited = 0.0
            add()
    add(final=True)


def main(argv):
    if len(argv) == 4 and argv[1] == "follow":
        follow(argv[2], argv[3])
    elif len(argv) == 4 and argv[1] == "clean":
        clean_file(argv[2], argv[3])
    else:
        sys.stderr.write(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
