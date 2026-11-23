"""Round 29 sounds, synthesised (no paid generator): numpy -> wav -> ffmpeg -> audio/sfx/<name>.ogg
    python3 tools/synth_round29.py
  megafire_roar   loop, mono: Thumper's Megafire, a deep blowtorch roar with a crackling hiss on top
  earthquake_slam stereo: Thumper's Earthquake Slam, an 808 sub drop (his lowrider music) + a cracking boom,
                  a wide stereo whoosh and a rumbling tail
  hellfire_horn   stereo: Brimstone's Hellfire Sermon, the gates of hell opening: a huge low brass horn on a
                  tritone, a shrieking upper horn, a sub swell, grinding stone, in a long cavern reverb"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")
rng = np.random.default_rng(29)


def t_(sec):
    return np.arange(int(sec * SR)) / SR


def band(x, lo, hi, soft=0.15):
    """Band-pass in the frequency domain with soft edges (lo/hi in Hz; lo 0 = low-pass)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo > 0:
        g *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** (2 / soft * 0.2))
    if hi > 0:
        g *= 1 / (1 + (np.maximum(f, 1e-3) / hi) ** (2 / soft * 0.2))
    return np.fft.irfft(X * g, len(x))


def brown(n):
    w = rng.standard_normal(n)
    b = np.cumsum(w)
    b -= np.convolve(b, np.ones(2000) / 2000, mode="same")  # keep it from wandering off
    return b / (np.abs(b).max() + 1e-9)


def env(n, a, d, sustain=1.0, r=None):
    e = np.ones(n) * sustain
    ia = int(a * SR)
    e[:ia] = np.linspace(0, 1, ia) ** 2 if ia else e[:ia]
    if r:
        ir = int(r * SR)
        e[-ir:] *= np.linspace(1, 0, ir) ** 1.5
    return e


def saw(freq_t):
    ph = np.cumsum(freq_t) / SR
    return 2.0 * (ph - np.floor(ph + 0.5))


def reverb(x, seconds, wet, seed):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir = r.standard_normal(n) * np.exp(-np.linspace(0, 6.5, n))
    ir = band(ir, 80, 3500)
    ir /= np.abs(ir).sum() ** 0.5 * 8
    y = np.fft.irfft(np.fft.rfft(x, len(x) + n) * np.fft.rfft(ir, len(x) + n), len(x) + n)
    out = np.zeros(len(x) + n)
    out[:len(x)] += x * (1 - wet)
    return out + y * wet


def save(name, data, stereo=False, peak_db=-1.0):
    data = np.asarray(data, dtype=np.float64)
    data = data / (np.abs(data).max() + 1e-9) * 10 ** (peak_db / 20)
    if stereo:
        pcm = (np.stack(data, axis=1) * 32767).astype(np.int16) if data.ndim == 2 else data
    else:
        pcm = (data * 32767).astype(np.int16)
    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
    os.remove(tmp)
    print("wrote", out)


# ---------------------------------------------------------------- Megafire roar (a seamless loop)
L = 3.0
n = int(L * SR)
base = brown(n + SR)
roar = band(base, 30, 420) * 1.0
hiss = band(rng.standard_normal(n + SR), 1800, 7000) * 0.22
crack = np.zeros(n + SR)
for k in range(140):  # little pops in the blowtorch
    i = rng.integers(0, n + SR - 400)
    crack[i:i + 300] += rng.standard_normal(300) * np.exp(-np.linspace(0, 8, 300)) * rng.uniform(0.2, 0.7)
crack = band(crack, 900, 6000) * 0.5
tt = np.arange(n + SR) / SR
rumble = np.sin(2 * np.pi * 52 * tt) * (0.55 + 0.45 * np.sin(2 * np.pi * 7.3 * tt)) * 0.35
x = roar * (0.8 + 0.2 * np.sin(2 * np.pi * 3.1 * tt)) + hiss + crack + rumble
fade = SR  # crossfade the extra second over the start: a loop without a click
x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[n:n + fade] * np.linspace(1, 0, fade)
save("megafire_roar", np.tanh(x[:n] * 1.6))

# ---------------------------------------------------------------- Earthquake Slam (stereo)
L = 3.2
n = int(L * SR)
tt = t_(L)
f = 35 + 85 * np.exp(-tt * 5.0)  # the 808 drop: 120 Hz down to 35
sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 1.3)
sub = np.tanh(sub * 2.2) * 0.9
click = np.zeros(n)
cl = int(0.03 * SR)
click[:cl] = rng.standard_normal(cl) * np.exp(-np.linspace(0, 9, cl))
crackle = band(rng.standard_normal(n), 500, 9000) * np.exp(-tt * 9) * 0.7
boom = band(rng.standard_normal(n), 25, 260) * np.exp(-tt * 3.2) * 1.4
rumble_l = band(rng.standard_normal(n), 20, 120) * np.exp(-tt * 1.1) * 0.6
rumble_r = band(rng.standard_normal(n), 20, 120) * np.exp(-tt * 1.1) * 0.6
# the wave rolling out: a whoosh sweeping from one ear to the other and back wider
sweep = np.zeros(n)
wn = band(rng.standard_normal(n), 300, 2600)
ew = np.exp(-((tt - 0.25) / 0.22) ** 2)
pan = 0.5 + 0.5 * np.sin(2 * np.pi * 1.6 * tt)
mono = sub + click * 0.9 + crackle + boom
left = mono + rumble_l + wn * ew * (1 - pan) * 0.6
right = mono + rumble_r + wn * ew * pan * 0.6
lr = reverb(left, 1.2, 0.25, 1)[:n], reverb(right, 1.2, 0.25, 2)[:n]
save("earthquake_slam", np.stack([np.tanh(lr[0] * 1.3), np.tanh(lr[1] * 1.3)]), stereo=True)

# ---------------------------------------------------------------- Hellfire horn (stereo): the gates of hell
L = 6.5
n = int(L * SR)
tt = t_(L)
vib = 1 + 0.006 * np.sin(2 * np.pi * 4.7 * tt) + 0.004 * np.sin(2 * np.pi * 0.7 * tt)
bend = 1 - 0.08 * np.exp(-tt * 2.5)  # it groans up into pitch
low = sum(saw(np.full(n, f0) * vib * bend * (1 + d)) for f0 in (41.2, 58.3) for d in (-0.004, 0.0, 0.005))  # E1 + its tritone
low = band(low, 30, 900)
upper = sum(saw(np.full(n, f0) * vib * (1 + d)) for f0 in (164.8, 233.1) for d in (-0.006, 0.006))
upper = band(upper, 300, 2400) * 0.35 * np.clip((tt - 1.2) / 1.5, 0, 1)  # the shriek joins later
sub = np.sin(2 * np.pi * 30.9 * tt) * 0.8
grind = band(brown(n), 40, 400) * 0.5 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.37 * tt)) ** 2
body = (np.tanh(low * 0.8) * 1.0 + upper + sub + grind) * env(n, 1.1, 0, 1.0, r=1.6)
gate = np.zeros(n)  # a massive door boom at the start
gl = int(1.5 * SR)
gate[:gl] = band(rng.standard_normal(gl), 20, 180) * np.exp(-np.linspace(0, 5, gl)) * 2.2
dry = body + gate
left = reverb(dry + band(rng.standard_normal(n), 60, 600) * 0.05, 3.5, 0.45, 7)
right = reverb(dry * 0.97 + band(rng.standard_normal(n), 60, 600) * 0.05, 3.6, 0.45, 8)
m = min(len(left), len(right))
save("hellfire_horn", np.stack([np.tanh(left[:m] * 1.2), np.tanh(right[:m] * 1.2)]), stereo=True)
