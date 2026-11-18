#!/usr/bin/env python3
"""Writes Nightfall's output to its log file, kept to a sane size.

    Nightfall.arm64 ... 2>&1 | python3 -I cap_log.py <log file> [max megabytes]

Two things, both because a log once grew by a thousand lines a second while
the headset lay unworn (2026-11-17: 89 MB in 23 minutes; overnight it would
have been gigabytes, written twice, since a cleaned copy is kept for sharing):

- A line, or a block of up to four lines, that keeps repeating is written
  once, followed by how many more times it came.
- Past the size limit (256 MB unless given) one last line says so and the rest
  is dropped. Input is read to its end regardless, so Nightfall is never held
  up by a full pipe.

Signals that stop the launcher are ignored here: this ends when Nightfall's
output does, so the last lines before an exit still reach the file.
"""
import signal
import sys
import time

MAX_PERIOD = 4
# Lines that are never written, by how they begin: the engine build's own
# line with what the eye tracker reads (steam-frame/engine, patch 0002).
NEVER_LOGGED = b"OpenXR: eye gaze reading"
# The same patch's line about eye-tracked foveation ends with the two points
# the eyes are looking at ("..., centres (x, y) (x, y)"). Whether the state is
# valid is worth keeping; where the eyes point is not written.
FOVEATION_STATE = b"OpenXR: eye-tracked foveation state:"
FOVEATION_CENTRES = b", centres"
DEFAULT_MAX_MB = 256
FLUSH_SECONDS = 0.5


class Capper:
    def __init__(self, out, max_bytes):
        self.out = out
        self.max_bytes = max_bytes
        self.written = 0
        self.full = False
        self.recent = []      # the last MAX_PERIOD lines written
        self.period = 0       # length of the block that is repeating, 0 for none
        self.matched = 0      # lines of the current repeat matched so far
        self.repeats = 0      # whole repeats swallowed

    def _write(self, data):
        if self.full:
            return
        if self.written + len(data) > self.max_bytes:
            note = b"== the log reached %d MB; nothing more is written to this file\n" % (self.max_bytes // (1024 * 1024))
            self.out.write(note)
            self.full = True
            return
        self.out.write(data)
        self.written += len(data)

    def _end_repeat(self):
        if self.period == 0:
            return
        pending = self.recent[len(self.recent) - self.period:][:self.matched]
        if self.repeats:
            what = b"line" if self.period == 1 else b"%d lines" % self.period
            self._write(b"== the previous %s came %d more time%s\n" % (what, self.repeats, b"" if self.repeats == 1 else b"s"))
        for line in pending:      # a repeat that broke off partway
            self._write(line)
        self.period = self.matched = self.repeats = 0

    def line(self, line):
        # Never written: the engine build's line with the eye tracker's
        # reading (a diagnostic of builds 6f on; the app's own gaze lines
        # are gone from the app itself).
        if line.startswith(NEVER_LOGGED):
            return
        if line.startswith(FOVEATION_STATE):
            line = line.split(FOVEATION_CENTRES, 1)[0].rstrip() + b"\n"
        if self.period:
            block = self.recent[len(self.recent) - self.period:]
            if line == block[self.matched]:
                self.matched += 1
                if self.matched == self.period:
                    self.matched = 0
                    self.repeats += 1
                return
            partial = self.matched
            self._end_repeat()
            if partial:
                # Those lines were written by _end_repeat; they are the newest now.
                self.recent = (self.recent + block[:partial])[-MAX_PERIOD:]
        for period in range(1, min(MAX_PERIOD, len(self.recent)) + 1):
            if line == self.recent[len(self.recent) - period]:
                # The start of a block seen before: begin matching it.
                self.period, self.matched, self.repeats = period, 1, 0
                if period == 1:
                    self.matched, self.repeats = 0, 1
                return
        self._write(line)
        self.recent = (self.recent + [line])[-MAX_PERIOD:]

    def close(self):
        self._end_repeat()


def run(source, target, max_bytes):
    with open(target, "wb") as out:
        capper = Capper(out, max_bytes)
        flushed = time.monotonic()
        for line in source:
            capper.line(line)
            now = time.monotonic()
            if now - flushed >= FLUSH_SECONDS:
                out.flush()
                flushed = now
        capper.close()


def self_test():
    import io

    def through(lines, max_bytes=1 << 30):
        out = io.BytesIO()
        capper = Capper(out, max_bytes)
        for line in lines:
            capper.line(line)
        capper.close()
        return out.getvalue().decode().splitlines()

    a, b, c = b"a\n", b"b\n", b"c\n"
    assert through([a, b, c]) == ["a", "b", "c"]
    assert through([a, a, a, a, b]) == ["a", "== the previous line came 3 more times", "b"]
    assert through([a, a]) == ["a", "== the previous line came 1 more time"]
    # The flood that prompted this: two lines, over and over.
    assert through([c] + [a, b] * 1000 + [c]) == ["c", "a", "b", "== the previous 2 lines came 999 more times", "c"]
    # A repeat that breaks off partway loses nothing.
    assert through([a, b, a, b, a, c]) == ["a", "b", "== the previous 2 lines came 1 more time", "a", "c"]
    assert through([a, b, a, c]) == ["a", "b", "a", "c"]
    # Lines that differ are never merged, whatever came before.
    assert through([a, b, c, a, b, c, a, b, c, a]) == ["a", "b", "c", "== the previous 3 lines came 2 more times", "a"]
    assert through([b"1\n", b"2\n", b"3\n", b"4\n", b"5\n", b"1\n"]) == ["1", "2", "3", "4", "5", "1"]
    # The eye tracker's reading never reaches the log, and leaving it out
    # doesn't disturb what is around it.
    gaze = b"OpenXR: eye gaze reading: action default_pose, orientation (0.1, 0.2, 0.3, 0.9)\n"
    assert through([a, gaze, b, gaze, gaze, c]) == ["a", "b", "c"]
    assert through([a, gaze, a, gaze, a]) == ["a", "== the previous line came 2 more times"]
    # Eye-tracked foveation: valid or not is kept, the points the eyes are
    # looking at are not, and the lines then fold like any repeat.
    fov = [b"OpenXR: eye-tracked foveation state: valid, centres (0.%d88, 0.021) (-0.128, 0.039)\n" % i for i in range(4)]
    assert through([a] + fov + [b]) == ["a", "OpenXR: eye-tracked foveation state: valid", "== the previous line came 3 more times", "b"]
    assert through([b"OpenXR: eye-tracked foveation state: not valid\n"]) == ["OpenXR: eye-tracked foveation state: not valid"]
    # The size limit: a last line, then nothing.
    capped = through([b"%099d\n" % i for i in range(50000)], max_bytes=2 * 1024 * 1024)
    assert capped[-1] == "== the log reached 2 MB; nothing more is written to this file", capped[-1]
    assert sum(len(line) + 1 for line in capped) <= 2 * 1024 * 1024 + 80
    print("cap_log self-test passed")


def main(argv):
    if len(argv) == 2 and argv[1] == "--self-test":
        self_test()
        return 0
    if len(argv) < 2:
        print(__doc__)
        return 2
    max_mb = int(argv[2]) if len(argv) > 2 else DEFAULT_MAX_MB
    for name in ("SIGINT", "SIGTERM", "SIGHUP"):
        signal.signal(getattr(signal, name), signal.SIG_IGN)
    run(sys.stdin.buffer, argv[1], max_mb * 1024 * 1024)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
