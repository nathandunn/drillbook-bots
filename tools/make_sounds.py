"""Drillbook Bots' sounds, made from nothing: no recordings, no downloads.

Run from the repo root:  python3 tools/make_sounds.py   (numpy + scipy) -> sounds/*.wav
Every sound is synthesised: a rifle-musket shot is a crack, a powder blast and a rolling
echo; a volley is a dozen of those spread over a third of a second; a cheer and a cry are
glottal pulses through vowel formants (the resonances of a throat saying "ah" or "oo").
"""
import numpy as np
from scipy.signal import butter, lfilter, sosfilt
from scipy.io import wavfile

SR = 22050
rng = np.random.default_rng(1861)


def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f / (SR / 2), btype="low", output="sos"), x)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f / (SR / 2), btype="high", output="sos"), x)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos"), x)


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def save(name, x):
    x = np.clip(norm(x), -1, 1)
    wavfile.write(f"sounds/{name}.wav", SR, (x * 32767).astype(np.int16))


def shot(dist=0.0, seed=0):
    r = np.random.default_rng(seed)
    n = int(1.3 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    # the crack: a few milliseconds of everything
    k = int(0.004 * SR)
    x[:k] += r.normal(0, 1, k) * np.linspace(1, 0, k) * 1.2
    # the powder blast: noise, quick to rise, quick to fall, darker the further away
    blast = r.normal(0, 1, n) * env_exp(n, 0.045 + 0.02 * r.random())
    x += lowpass(blast, 2600 - 1800 * dist + 600 * r.random(), 2) * 1.6
    # the thump in the chest
    f0 = 55 + 25 * r.random()
    x += np.sin(2 * np.pi * f0 * t) * env_exp(n, 0.09) * (1.2 - 0.5 * dist)
    # the roll of it across the field: low rumble that dies over a second
    roll = lowpass(r.normal(0, 1, n), 380, 2) * env_exp(n, 0.32)
    roll *= np.clip(t / 0.03, 0, 1)
    x += roll * (0.9 + 0.6 * dist)
    # a slap back off the treeline
    d = int((0.11 + 0.08 * r.random()) * SR)
    echo = np.zeros(n)
    echo[d:] = lowpass(x[:-d], 1200) * 0.35
    x += echo
    return x * (1.0 - 0.45 * dist)


def volley(seed):
    r = np.random.default_rng(seed)
    n = int(2.2 * SR)
    x = np.zeros(n)
    for i in range(14):
        s = shot(dist=r.random() * 0.8, seed=seed * 100 + i)
        o = int(abs(r.normal(0, 0.09)) * SR) + int(r.random() * 0.06 * SR)
        m = min(len(s), n - o)
        x[o:o + m] += s[:m] * (0.6 + 0.4 * r.random())
    return x


# ---------------------------------------------------------------- voices

FORMANTS = {   # F1, F2, F3 (Hz) and their bandwidths
    "a": ([730, 1090, 2440], [90, 110, 160]),
    "o": ([570, 840, 2410], [80, 100, 160]),
    "u": ([300, 870, 2240], [60, 90, 150]),
    "e": ([530, 1840, 2480], [70, 110, 160]),
    "uh": ([520, 1190, 2390], [80, 110, 160]),
}


def glottal(f0_curve, jitter=0.01, breath=0.08, r=None):
    """A pulse train following f0 (Hz per sample): the buzz of a throat before the mouth shapes it."""
    r = r or rng
    f = f0_curve * (1 + jitter * lowpass(r.normal(0, 1, len(f0_curve)), 30) * 10)
    ph = np.cumsum(f / SR)
    saw = 2 * (ph % 1.0) - 1
    src = lowpass(-saw, 3500, 1)          # a falling sawtooth, rolled off: near enough a glottal pulse
    src += r.normal(0, breath, len(f))     # air through it
    return src


def vowel(src, v):
    fs, bw = FORMANTS[v]
    out = np.zeros_like(src)
    for f, b, g in zip(fs, bw, [1.0, 0.6, 0.25]):
        out += bandpass(src, max(f - b, 40), f + b, 2) * g
    return out


def morph(src, v1, v2, t_switch, width=0.08):
    """Say v1 then v2, crossfading at t_switch seconds."""
    a = vowel(src, v1)
    b = vowel(src, v2)
    t = np.arange(len(src)) / SR
    w = np.clip((t - t_switch) / width + 0.5, 0, 1)
    return a * (1 - w) + b * w


def adsr(n, a, d_start, d):
    t = np.arange(n) / SR
    e = np.clip(t / a, 0, 1)
    e *= np.where(t > d_start, np.exp(-(t - d_start) / d), 1.0)
    return e


def hurrah(seed, voices=18):
    """A company going in: 'hu-RRAH', a crowd of men, ragged, rising."""
    r = np.random.default_rng(seed)
    n = int(2.0 * SR)
    x = np.zeros(n)
    for i in range(voices):
        base = r.uniform(105, 175)
        o = int(r.uniform(0, 0.28) * SR)
        m = n - o
        t = np.arange(m) / SR
        # 'hu' low and short, then the 'rrah' leaps up and holds, then cracks down
        f0 = np.where(t < 0.22, base * 0.9, base * (1.45 + 0.25 * np.clip((t - 0.22) / 0.4, 0, 1)))
        f0 = f0 * np.where(t > 1.1, np.exp(-(t - 1.1) * 0.8), 1.0)
        f0 = lowpass(f0, 12, 1)
        src = glottal(f0, jitter=0.02, breath=0.25, r=r)
        v = morph(src, "u", "a", 0.22, 0.06)
        # the rolled r: a flutter on the amplitude at the change
        flutter = 1 - 0.5 * np.exp(-((t - 0.25) / 0.05) ** 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 28 * t))
        e = adsr(m, 0.04, 1.0 + r.uniform(0, 0.4), 0.18) * flutter
        x[o:] += v * e * r.uniform(0.5, 1.0)
    # a crowd is a room: a little smear
    for dly, g in [(0.031, 0.4), (0.067, 0.25), (0.13, 0.15)]:
        k = int(dly * SR)
        x[k:] += x[:-k] * g
    return highpass(x, 90)


def cry(seed):
    """A man hit: a sharp 'AH!' breaking into a moan."""
    r = np.random.default_rng(seed)
    dur = r.uniform(0.7, 1.1)
    n = int(dur * SR)
    t = np.arange(n) / SR
    top = r.uniform(230, 360)
    f0 = top * (1.0 - 0.45 * np.clip(t / dur, 0, 1)) * (1 + 0.04 * np.sin(2 * np.pi * r.uniform(5, 8) * t))
    src = glottal(f0, jitter=0.05, breath=0.35, r=r)
    v = morph(src, "a", "uh", dur * 0.55, 0.2)
    e = adsr(n, 0.015, 0.12, dur * 0.45)
    return highpass(v * e, 120)


def groan(seed):
    """The last of a man: low, breathy, falling."""
    r = np.random.default_rng(seed)
    dur = r.uniform(0.6, 0.9)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = r.uniform(95, 135) * (1.0 - 0.35 * t / dur)
    src = glottal(f0, jitter=0.06, breath=0.5, r=r)
    v = morph(src, "o", "uh", dur * 0.4, 0.2)
    e = adsr(n, 0.05, 0.15, dur * 0.35)
    return highpass(v * e, 80) * 0.8


def scream(seed):
    """A man running: high and long."""
    r = np.random.default_rng(seed)
    dur = r.uniform(0.9, 1.3)
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = r.uniform(380, 480) * (1 + 0.06 * np.sin(2 * np.pi * 6.5 * t)) * (1 - 0.2 * t / dur)
    src = glottal(f0, jitter=0.03, breath=0.3, r=r)
    v = vowel(src, "e")
    e = adsr(n, 0.03, dur * 0.6, dur * 0.2)
    return highpass(v * e, 200)


def bark(seed):
    """A sergeant: one short loud syllable - 'FIRE!' near enough, without the words."""
    r = np.random.default_rng(seed)
    dur = 0.42
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = r.uniform(140, 175) * (1.25 - 0.4 * t / dur)
    src = glottal(f0, jitter=0.015, breath=0.2, r=r)
    v = morph(src, "a", "e", 0.18, 0.08)
    fric = highpass(r.normal(0, 1, n), 2500) * np.exp(-t / 0.04) * 0.6   # the 'f'
    e = adsr(n, 0.02, 0.25, 0.08)
    return highpass(v * e, 110) + fric


def clash(seed):
    """Steel on steel: inharmonic ringing and a click."""
    r = np.random.default_rng(seed)
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f in r.uniform(1800, 7500, 5):
        x += np.sin(2 * np.pi * f * t + r.uniform(0, 6)) * np.exp(-t / r.uniform(0.05, 0.22)) * r.uniform(0.3, 1)
    k = int(0.003 * SR)
    x[:k] += r.normal(0, 1, k) * 2
    return x * 0.7


def thud(seed):
    """A body hitting the ground."""
    r = np.random.default_rng(seed)
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    x = lowpass(r.normal(0, 1, n), 300) * np.exp(-t / 0.06)
    x += np.sin(2 * np.pi * r.uniform(60, 90) * t) * np.exp(-t / 0.08)
    return x


if __name__ == "__main__":
    for i in range(4):
        save(f"shot_{i}", shot(dist=0.0, seed=10 + i))
    for i in range(2):
        save(f"volley_{i}", volley(20 + i))
    for i in range(3):
        save(f"hurrah_{i}", hurrah(30 + i))
    for i in range(5):
        save(f"cry_{i}", cry(40 + i))
    for i in range(3):
        save(f"groan_{i}", groan(50 + i))
    for i in range(3):
        save(f"scream_{i}", scream(60 + i))
    for i in range(2):
        save(f"bark_{i}", bark(70 + i))
    for i in range(3):
        save(f"clash_{i}", clash(80 + i))
    for i in range(2):
        save(f"thud_{i}", thud(90 + i))
    print("ok")
