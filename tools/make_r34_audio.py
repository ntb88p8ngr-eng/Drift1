"""Cuts the R34 recordings into the sample sets used by scripts/car/car_audio.gd.

Usage:  python3 tools/make_r34_audio.py <dyno.mp3> <engine.mp3> <turbo.mp3>
Needs:  numpy, scipy, soundfile (pip install numpy scipy soundfile)

dyno.mp3   – "R34 SKYLINE DYNO TEST (COMPILATION)": long full-load pull (on-load sound)
engine.mp3 – "Top Speed Autosport HKS Hi-Power Exhaust Nissan GTR R34": rev-down (off-load) and idle
turbo.mp3  – "Nissan Skyline GTR R34 Turbo Sound": turbo whistle, blow-off with compressor flutter

Engine: the dyno pull (on-load; strongest line = firing frequency, 3rd order, rpm = f * 20) and the
HKS rev-down (off-load; strongest line = 4.5th order) are tracked and time-warped so that the tracked
line has a constant pitch (F_REF_*). The game picks the position whose recorded rpm matches the current
rpm and plays short, phase-aligned grains at rate = f_target / F_REF, so timbre and pitch follow the rpm.
The idle is a seamless loop. Turbo: the whistle rise is warped the same way (driven by boost); the
lift-off events (blow-off "pssst" + flutter + falling whistle) are high-passed one-shots.

Output: assets/audio/r34_*.bin (float32 LE, mono, 22050 Hz) and scripts/car/r34_sound_data.gd.
"""
import sys, os
import numpy as np
import soundfile as sf
from scipy import signal

OUT_RATE = 22050
ON_ORDER = 3.0       # dyno: tracked line = firing frequency
OFF_ORDER = 4.5      # HKS rev-down: tracked line = 4.5th order
F_REF_ON = 65.0      # on-load buffer normalized to this line frequency (Hz)
F_REF_OFF = 75.0     # off-load buffer normalization (Hz)
F_REF_TURBO = 2800.0 # turbo whistle buffer normalization (Hz)

# (start s, end s, initial line frequency Hz)
DYNO_PULL = (6.95, 23.5, 71.0)          # full-load pull, ~1400 -> ~6000 rpm
ENGINE_DECAY = (8.36, 10.75, 345.0)     # HKS lift-off rev-down (off-load)
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


def harmonic_clean(x, f0, fs=22050, floor=0.1, rel=0.006, min_bw=0.8):
    """Pitch-normalized engine buffer: everything the engine makes lies on multiples of f0 (half the
    crank order). Keeps those lines and lowers what lies between them by 20 dB – the dyno's broadband
    roller/fan rumble that was audible when lifting off."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / fs)
    d = np.abs(f - np.round(f / f0) * f0)
    g = np.exp(-0.5 * (d / np.maximum(min_bw, rel * f)) ** 2)
    return np.fft.irfft(X * (floor + (1 - floor) * g), n).astype(np.float32)


def write_bin(path, x):
    np.asarray(x, dtype="<f4").tofile(path)
    print("  wrote %s (%.2f s)" % (path, len(x) / OUT_RATE))


def main():
    dyno_path, eng_path, turbo_path = sys.argv[-3], sys.argv[-2], sys.argv[-1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)

    # ---------------- engine ----------------
    dm, dfs = load(dyno_path)
    dml = lowpass(dm, dfs, 10500)
    t_on, f_on = track(dm, dfs, *DYNO_PULL, lo=0.95, hi=1.05, harm=(1, 2, 3), smooth=81)
    f_on = np.maximum.accumulate(f_on)
    on, on_f = warp(dml, dfs, t_on, f_on, F_REF_ON)
    on = fade(on, 400, 400)

    m, fs = load(eng_path)
    ml = lowpass(m, fs, 10500)
    t_dn, f_dn = track(m, fs, *ENGINE_DECAY, lo=0.9, hi=1.06)
    f_dn = np.minimum.accumulate(f_dn)
    off, off_f = warp(ml, fs, t_dn, f_dn, F_REF_OFF)
    idle = resample(ml[int(ENGINE_IDLE[0] * fs):int(ENGINE_IDLE[1] * fs)], fs)
    idle = make_loop(idle, int(0.35 * OUT_RATE))
    # idle rpm: the firing frequency (3rd order) is the strongest idle peak between 45 and 65 Hz
    fq, P = signal.welch(ml[int(ENGINE_IDLE[0] * fs):int(ENGINE_IDLE[1] * fs)], fs, nperseg=32768)
    sel = (fq > 45) & (fq < 65)
    idle_rpm = float(fq[sel][np.argmax(P[sel])]) * 20.0
    # levels: full load loudest, lift-off a bit quieter, idle quiet
    rms = lambda a: float(np.sqrt(np.mean(a ** 2)))
    on *= 0.9 / np.abs(on).max()
    off *= (0.62 * rms(on)) / rms(off)
    idle *= (0.4 * rms(on)) / rms(idle)
    print("engine: on %.0f-%.0f rpm, off %.0f-%.0f rpm, idle %.0f rpm" % (
        on_f.min() * 60 / ON_ORDER, on_f.max() * 60 / ON_ORDER, off_f.min() * 60 / OFF_ORDER,
        off_f.max() * 60 / OFF_ORDER, idle_rpm))

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
    # off-load buffer: F_REF_OFF is the 4.5th order -> half order = F_REF_OFF / 9
    level = rms(off)
    off = harmonic_clean(off, F_REF_OFF / 9.0)
    off *= level / rms(off)   # same loudness as before the cleaning
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
        "const ON_ORDER := %.2f" % ON_ORDER,
        "const OFF_ORDER := %.2f" % OFF_ORDER,
        "const F_REF_ON := %.2f" % F_REF_ON,
        "const F_REF_OFF := %.2f" % F_REF_OFF,
        "const F_REF_TURBO := %.2f" % F_REF_TURBO,
        "const TABLE_STEP := %d" % step,
        "const IDLE_RPM := %.1f" % idle_rpm,
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
