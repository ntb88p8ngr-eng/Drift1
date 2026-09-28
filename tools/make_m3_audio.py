"""Cuts the BMW E90 M3 (S65 V8) recordings into the sample set used by scripts/car/car_audio.gd.

Usage:  python3 tools/make_m3_audio.py <backbox.mp3> <stock.mp3>
Needs:  numpy, scipy, soundfile (pip install numpy scipy soundfile)

backbox.mp3 – "BMW E90 M3 Megan Racing Supremo Back box sound check": the main sound. Idle (~650 rpm)
and throttle blips, but only up to ~2950 rpm.
stock.mp3 – "BMW E90 M3 S65 V8 4.0 Original Stock Exhaust Pure Sound": its free-rev blips reach
~7100 rpm and fill the range above.

Line tracked: V8 firing frequency (4th order, rpm = f * 15). The back-box clip carries little of
the fundamental, so it is followed through its 2nd-4th harmonics.

On-load: the back-box blip (~650 -> 2950 rpm), then the stock clip's rev-up ramps above that; all
warped to a constant line pitch (F_REF_ON) and joined where their frequencies meet, with levels
matched at the joins. Off-load: the stock rev-down from ~7000 rpm to the back-box range, then the
back-box rev-down to idle. Idle: the steady first seconds of the back-box clip as a seamless loop.

Output: assets/audio/m3_*.bin (float32 LE, mono, 22050 Hz) and scripts/car/m3_sound_data.gd.
"""
import sys, os
import numpy as np
from scipy import signal
from make_r34_audio import (OUT_RATE, load, track, warp, lowpass, resample, crossfade_join, make_loop,
                            table, fade, write_bin)

ORDER = 4.0          # V8 firing frequency
F_REF_ON = 90.0
F_REF_OFF = 90.0

# back-box clip: the big blip (rev-up), its rev-down, the idle before it
BB_RAMP = (5.95, 6.95, 45.0)
BB_DECAY_END = 9.6
BB_IDLE = (0.3, 2.3)
# stock clip: (start s, end s, initial line frequency Hz) – rev-up ramps used above the back-box range
RAMPS = [(13.56, 14.07, 150.0), (24.93, 25.08, 420.0)]
DECAY = (25.12, 29.8, 470.0)


def _rms(a):
    return float(np.sqrt(np.mean(a ** 2)))


def _join(buf, buf_f, seg, seg_f):
    """Appends seg to buf with a short crossfade; seg is levelled to the end of buf first."""
    if buf is None:
        return seg, seg_f
    n = int(0.012 * OUT_RATE)
    w = int(0.08 * OUT_RATE)
    seg = seg * (_rms(buf[-w:]) / max(_rms(seg[:w]), 1e-6))
    return crossfade_join(buf, seg, n), np.concatenate([buf_f[:-n], seg_f])


def main():
    bb_path, stock_path = sys.argv[-2], sys.argv[-1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)

    bb, fs_b = load(bb_path)
    bbl = lowpass(bb, fs_b, 10500)
    st, fs_s = load(stock_path)
    stl = lowpass(st, fs_s, 10500)

    # on-load: back-box blip up to its peak ...
    t, f = track(bb, fs_b, *BB_RAMP, lo=0.95, hi=1.12, harm=(2, 3, 4), smooth=9)
    f = np.maximum.accumulate(f)
    top = int(np.argmax(f >= f.max() * 0.995))
    t_peak = float(t[top])
    on, on_f = warp(bbl, fs_b, t[:top + 1], f[:top + 1], F_REF_ON)
    # ... then the stock ramps above it
    for (a, b, f0) in RAMPS:
        t, f = track(st, fs_s, a, b, f0, lo=0.95, hi=1.08, harm=(1, 2), smooth=15, hop=120)
        f = np.maximum.accumulate(f)
        keep = f > on_f[-1]
        if keep.sum() < 8:
            continue
        seg, seg_f = warp(stl, fs_s, t[keep], f[keep], F_REF_ON)
        on, on_f = _join(on, on_f, seg, seg_f)
    on = fade(on, 300, 300)

    # off-load: stock rev-down from the top to the back-box range, then the back-box rev-down
    t_b, f_b = track(bb, fs_b, t_peak, BB_DECAY_END, _peak_f(bb, fs_b, t_peak), lo=0.9, hi=1.06, harm=(2, 3, 4), smooth=21)
    f_b = np.minimum.accumulate(f_b)
    t_s, f_s = track(st, fs_s, *DECAY, lo=0.9, hi=1.06, harm=(1, 2), smooth=41)
    f_s = np.minimum.accumulate(f_s)
    keep = f_s > f_b[0]
    off, off_f = warp(stl, fs_s, t_s[keep], f_s[keep], F_REF_OFF)
    seg, seg_f = warp(bbl, fs_b, t_b, f_b, F_REF_OFF)
    off, off_f = _join(off, off_f, seg, seg_f)
    off = fade(off, 300, 300)

    idle = resample(bbl[int(BB_IDLE[0] * fs_b):int(BB_IDLE[1] * fs_b)], fs_b)
    idle = make_loop(idle, int(0.35 * OUT_RATE))
    fq, P = signal.welch(bbl[int(BB_IDLE[0] * fs_b):int(BB_IDLE[1] * fs_b)], fs_b, nperseg=32768)
    # the idle shows best as the 3rd harmonic of the firing frequency (~130 Hz)
    sel = (fq > 110) & (fq < 150)
    idle_rpm = float(fq[sel][np.argmax(P[sel])]) / 3.0 * 60.0 / ORDER

    rms = lambda a: float(np.sqrt(np.mean(a ** 2)))
    # match the R34 levels (on-load rms ~0.3); the few blip peaks above that are soft-limited
    on *= 0.3 / rms(on)
    on = 0.95 * np.tanh(on / 0.95)
    off *= (0.64 * rms(on)) / rms(off)
    off = 0.95 * np.tanh(off / 0.95)
    idle *= (0.45 * rms(on)) / rms(idle)
    print("engine: on %.0f-%.0f rpm (%.2f s), off %.0f-%.0f rpm (%.2f s), idle %.0f rpm" % (
        on_f.min() * 15, on_f.max() * 15, len(on) / OUT_RATE, off_f.min() * 15, off_f.max() * 15,
        len(off) / OUT_RATE, idle_rpm))

    write_bin(os.path.join(out_dir, "m3_engine_on.bin"), on)
    write_bin(os.path.join(out_dir, "m3_engine_off.bin"), off)
    write_bin(os.path.join(out_dir, "m3_idle.bin"), idle)

    step = 64
    gd = [
        "extends RefCounted",
        "## Generated by tools/make_m3_audio.py – sample tables for the M3 (S65 V8) engine sound.",
        "## *_F tables: tracked line frequency (Hz) every %d samples of the matching buffer." % step,
        "",
        "const PREFIX := \"m3\"",
        "const RATE := %d" % OUT_RATE,
        "const ON_ORDER := %.2f" % ORDER,
        "const OFF_ORDER := %.2f" % ORDER,
        "const F_REF_ON := %.2f" % F_REF_ON,
        "const F_REF_OFF := %.2f" % F_REF_OFF,
        "const F_REF_TURBO := 1.0",
        "const TABLE_STEP := %d" % step,
        "const GAIN := 1.55",
        "const IDLE_RPM := %.1f" % idle_rpm,
        "const LIFT_COUNT := 0",
        "const ON_F := %s" % table(on_f, step),
        "const OFF_F := %s" % table(off_f, step),
        "const SPOOL_F := []",
        "",
    ]
    with open(os.path.join(root, "scripts", "car", "m3_sound_data.gd"), "w") as f:
        f.write("\n".join(gd))
    print("done")


def _peak_f(m, fs, t0):
    """Firing frequency right at t0 (the top of the blip), from the 3rd harmonic."""
    x = m[int(t0 * fs) - 2048:int(t0 * fs) + 2048] * np.hanning(4096)
    X = np.abs(np.fft.rfft(x, 1 << 16))
    fq = np.fft.rfftfreq(1 << 16, 1 / fs)
    sel = (fq > 300) & (fq < 800)
    return float(fq[sel][np.argmax(X[sel])]) / 3.0


if __name__ == "__main__":
    main()
