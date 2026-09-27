"""Cuts the two R34 recordings into the sample sets used by scripts/car/car_audio.gd.

Usage:  python3 tools/make_r34_audio.py <engine.mp3> <turbo.mp3>
Needs:  numpy, scipy, soundfile (pip install numpy scipy soundfile)

engine.mp3 – "Top Speed Autosport HKS Hi-Power Exhaust Nissan GTR R34" (revs in place + idle)
turbo.mp3  – "Nissan Skyline GTR R34 Turbo Sound" (turbo whistle, blow-off with compressor flutter)

Engine: the rev-ups (on-load) and the long rev-down (off-load) are tracked (strongest engine-order line,
4.5th order: rpm = f * 60 / 4.5) and time-warped so that this line has a constant pitch (F_REF). The game
then picks the position whose recorded rpm matches the current rpm and plays short, phase-aligned
grains at rate = f_target / F_REF, so timbre and pitch both follow the rpm. The idle is a seamless loop.
Turbo: the whistle rise is warped the same way (driven by boost); the lift-off events (blow-off
"pssst" + flutter + falling whistle) are high-passed one-shots.

Output: assets/audio/r34_*.bin (float32 LE, mono, 22050 Hz) and scripts/car/r34_sound_data.gd.
"""
import sys, os
import numpy as np
import soundfile as sf
from scipy import signal

OUT_RATE = 22050
ORDER = 4.5          # engine order of the tracked line
F_REF = 75.0         # engine buffers are normalized to this line frequency (Hz)
F_REF_TURBO = 2800.0 # turbo whistle buffer normalization (Hz)

# (start s, end s, initial line frequency Hz) – see the spectrograms in the commit description
ENGINE_REV_LOW = (3.60, 4.46, 82.0)     # rev-up used below the join frequency
ENGINE_REV_HIGH = (7.66, 8.28, 162.0)   # cleanest rev-up, used above the join
ENGINE_JOIN_HZ = 162.0
ENGINE_DECAY = (8.36, 10.75, 345.0)     # lift-off rev-down (off-load)
ENGINE_IDLE = (11.2, 17.9)
TURBO_RISE = (9.18, 9.95, 3050.0)       # whistle spool-up
TURBO_LIFTS = [(8.10, 1.25), (9.95, 2.0), (14.20, 1.0), (15.70, 1.6)]   # (peak time, length)


def load(path):
    d, fs = sf.read(path)
    m = d.mean(axis=1) if d.ndim > 1 else d
    return m.astype(np.float64), fs


def track(m, fs, a, b, f_start, lo=0.93, hi=1.1, nper=4096, hop=120, harm=(1, 2), smooth=61):
    """Follows one harmonic line from f_start; returns (times, freqs), smoothed."""
    seg = m[int(a * fs):int(b * fs)]
    nfft = 32768
    win = signal.windows.hann(nper)
    pad = np.concatenate([np.zeros(nper // 2), seg, np.zeros(nper // 2)])
    df = fs / nfft
    times, fr = [], []
    f = f_start
    for i in range(len(seg) // hop):
        x = pad[i * hop:i * hop + nper]
        if len(x) < nper:
            break
        X = np.abs(np.fft.rfft(x * win, nfft))
        cands = np.arange(f * lo, f * hi, df / 2)
        sc = np.zeros(len(cands))
        for h in harm:
            idx = cands * h / df
            i0 = np.floor(idx).astype(int)
            fr_ = idx - i0
            ok = i0 + 1 < len(X)
            v = np.zeros(len(cands))
            v[ok] = X[i0[ok]] * (1 - fr_[ok]) + X[i0[ok] + 1] * fr_[ok]
            sc += v / h ** 0.5
        j = int(np.argmax(sc))
        fb = cands[j]
        if 0 < j < len(sc) - 1:
            y0, y1, y2 = sc[j - 1], sc[j], sc[j + 1]
            den = y0 - 2 * y1 + y2
            if den != 0:
                fb += 0.5 * (y0 - y2) / den * (cands[1] - cands[0])
        times.append(a + i * hop / fs)
        fr.append(fb)
        f = fb
    fr = np.array(fr)
    if len(fr) > smooth:
        fr = signal.savgol_filter(fr, smooth, 2)
    return np.array(times), fr


def warp(x, fs, times, freqs, f_ref):
    """Time-warps x so the tracked line sits at f_ref. Returns (buffer @ OUT_RATE, line freq per output sample)."""
    phase = np.concatenate([[0.0], np.cumsum(0.5 * (freqs[1:] + freqs[:-1]) * np.diff(times))])
    n_out = int(phase[-1] * OUT_RATE / f_ref)
    ph_out = np.arange(n_out) * f_ref / OUT_RATE
    t_out = np.interp(ph_out, phase, times)
    f_out = np.interp(t_out, times, freqs)
    s = t_out * fs
    i0 = np.floor(s).astype(int)
    fr = s - i0
    xm1 = x[np.clip(i0 - 1, 0, len(x) - 1)]
    x0 = x[np.clip(i0, 0, len(x) - 1)]
    x1 = x[np.clip(i0 + 1, 0, len(x) - 1)]
    x2 = x[np.clip(i0 + 2, 0, len(x) - 1)]
    # Catmull-Rom interpolation
    y = x0 + 0.5 * fr * (x1 - xm1 + fr * (2 * xm1 - 5 * x0 + 4 * x1 - x2 + fr * (3 * (x0 - x1) + x2 - xm1)))
    return y, f_out


def lowpass(x, fs, fc, order=8):
    sos = signal.butter(order, fc, "low", fs=fs, output="sos")
    return signal.sosfiltfilt(sos, x)


def highpass(x, fs, fc, order=4):
    sos = signal.butter(order, fc, "high", fs=fs, output="sos")
    return signal.sosfiltfilt(sos, x)


def resample(x, fs):
    g = np.gcd(int(fs), OUT_RATE)
    return signal.resample_poly(x, OUT_RATE // g, int(fs) // g)


def crossfade_join(a, b, n):
    n = min(n, len(a), len(b))
    w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))
    return np.concatenate([a[:-n], a[-n:] * (1 - w) + b[:n] * w, b[n:]])


def make_loop(x, n):
    """Seamless loop: the last n samples fade into the first n."""
    w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))
    body = x[n:].copy()
    body[-n:] = body[-n:] * (1 - w) + x[:n] * w
    return body


def table(values, step=64):
    idx = np.arange(0, len(values), step)
    return [round(float(values[i]), 2) for i in idx]


def fade(x, fin, fout):
    y = x.copy()
    if fin > 0:
        y[:fin] *= np.linspace(0, 1, fin)
    if fout > 0:
        y[-fout:] *= np.linspace(1, 0, fout) ** 2
    return y


def write_bin(path, x):
    np.asarray(x, dtype="<f4").tofile(path)
    print("  wrote %s (%.2f s)" % (path, len(x) / OUT_RATE))


def main():
    eng_path, turbo_path = sys.argv[-2], sys.argv[-1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)

    # ---------------- engine ----------------
    m, fs = load(eng_path)
    ml = lowpass(m, fs, 10500)
    t_lo, f_lo = track(m, fs, *ENGINE_REV_LOW)
    t_hi, f_hi = track(m, fs, *ENGINE_REV_HIGH)
    t_dn, f_dn = track(m, fs, *ENGINE_DECAY, lo=0.9, hi=1.06)
    # low rev-up: up to the join frequency; high rev-up: from the join to its peak
    k = np.searchsorted(f_lo, ENGINE_JOIN_HZ)
    t_lo, f_lo = t_lo[:k], f_lo[:k]
    peak = int(np.argmax(f_hi))
    k2 = np.searchsorted(f_hi[:peak], ENGINE_JOIN_HZ)
    t_hi, f_hi = t_hi[k2:peak], f_hi[k2:peak]
    y_lo, fl_lo = warp(ml, fs, t_lo, np.maximum.accumulate(f_lo), F_REF)
    y_hi, fl_hi = warp(ml, fs, t_hi, np.maximum.accumulate(f_hi), F_REF)
    xf = int(2 * OUT_RATE / F_REF)
    on = crossfade_join(y_lo, y_hi, xf)
    on_f = np.concatenate([fl_lo[:-xf], fl_hi[:len(on) - len(fl_lo) + xf]])
    f_dn = np.minimum.accumulate(f_dn)
    off, off_f = warp(ml, fs, t_dn, f_dn, F_REF)
    idle = resample(ml[int(ENGINE_IDLE[0] * fs):int(ENGINE_IDLE[1] * fs)], fs)
    idle = make_loop(idle, int(0.35 * OUT_RATE))
    # idle rpm: the firing frequency (3rd order) is the strongest idle peak between 45 and 65 Hz;
    # convert it to the tracked 4.5th-order line
    fq, P = signal.welch(ml[int(ENGINE_IDLE[0] * fs):int(ENGINE_IDLE[1] * fs)], fs, nperseg=32768)
    sel = (fq > 45) & (fq < 65)
    idle_line = float(fq[sel][np.argmax(P[sel])]) * ORDER / 3.0
    gain = 0.92 / max(np.abs(on).max(), np.abs(off).max(), np.abs(idle).max())
    on, off, idle = on * gain, off * gain, idle * gain
    rpm = 60.0 / ORDER
    print("engine: on %.0f-%.0f rpm, off %.0f-%.0f rpm, idle line %.1f Hz (%.0f rpm)" % (
        on_f.min() * rpm, on_f.max() * rpm, off_f.min() * rpm, off_f.max() * rpm, idle_line, idle_line * rpm))

    # ---------------- turbo ----------------
    tm, tfs = load(turbo_path)
    th = lowpass(highpass(tm, tfs, 1100), tfs, 10500)
    t_w, f_w = track(tm, tfs, *TURBO_RISE, lo=0.95, hi=1.08, nper=2048, hop=96, harm=(1, 2), smooth=31)
    f_w = np.maximum.accumulate(f_w)
    spool, spool_f = warp(th, tfs, t_w, f_w, F_REF_TURBO)
    spool = fade(spool, 200, 200) * (0.9 / np.abs(spool).max())
    lifts = []
    for (tp, length) in TURBO_LIFTS:
        seg = th[int((tp - 0.03) * tfs):int((tp + length) * tfs)]
        seg = resample(seg, tfs)
        seg = fade(seg, int(0.006 * OUT_RATE), int(0.35 * OUT_RATE))
        lifts.append(seg * (0.9 / np.abs(seg).max()))
    print("turbo: whistle %.0f-%.0f Hz, %d lift-off samples" % (spool_f.min(), spool_f.max(), len(lifts)))

    write_bin(os.path.join(out_dir, "r34_engine_on.bin"), on)
    write_bin(os.path.join(out_dir, "r34_engine_off.bin"), off)
    write_bin(os.path.join(out_dir, "r34_idle.bin"), idle)
    write_bin(os.path.join(out_dir, "r34_turbo_spool.bin"), spool)
    for i, l in enumerate(lifts):
        write_bin(os.path.join(out_dir, "r34_turbo_lift_%d.bin" % (i + 1)), l)

    step = 64
    gd = [
        "extends RefCounted",
        "## Generated by tools/make_r34_audio.py – sample tables for the R34 engine and turbo sounds.",
        "## *_F tables: tracked line frequency (Hz) every %d samples of the matching buffer." % step,
        "",
        "const RATE := %d" % OUT_RATE,
        "const ORDER := %.2f" % ORDER,
        "const F_REF := %.2f" % F_REF,
        "const F_REF_TURBO := %.2f" % F_REF_TURBO,
        "const TABLE_STEP := %d" % step,
        "const IDLE_LINE := %.2f" % idle_line,
        "const LIFT_COUNT := %d" % len(lifts),
        "const ON_F := %s" % table(on_f, step),
        "const OFF_F := %s" % table(off_f, step),
        "const SPOOL_F := %s" % table(spool_f, step),
        "",
    ]
    with open(os.path.join(root, "scripts", "car", "r34_sound_data.gd"), "w") as f:
        f.write("\n".join(gd))
    print("done")


if __name__ == "__main__":
    main()
