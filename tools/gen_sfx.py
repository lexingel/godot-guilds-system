"""Synthesizes the game's extra sound effects into assets/audio/sfx/gen_*.wav
(retro, sfxr-style — they sit alongside the Kenney set). Deterministic:
re-running produces the same files. Usage: python tools/gen_sfx.py"""
import os, wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
rng = np.random.default_rng(7)


def t(d):
    return np.linspace(0, d, int(SR * d), endpoint=False)


def env(n, a=0.01, r=None):
    """Attack then exponential decay (or linear release over r seconds)."""
    e = np.ones(n)
    na = max(1, int(SR * a))
    e[:na] = np.linspace(0, 1, na)
    if r is None:
        e[na:] = np.exp(-np.linspace(0, 5, n - na))
    else:
        nr = min(n - na, int(SR * r))
        e[n - nr:] *= np.linspace(1, 0, nr)
    return e


def sweep(f0, f1, d, shape=np.sin):
    tt = t(d)
    f = np.linspace(f0, f1, tt.size)
    return shape(2 * np.pi * np.cumsum(f) / SR)


def square(x):
    return np.sign(np.sin(x))


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same")


def tone(freq, d, shape=np.sin):
    return shape(2 * np.pi * freq * t(d))


def save(name, x, vol=0.55):
    x = x / (np.max(np.abs(x)) + 1e-9) * vol
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, "gen_%s.wav" % name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def seq(parts):
    return np.concatenate(parts)


# A foe winds up: rising rumble.
d = 0.55
save("windup", (sweep(60, 220, d, square) * 0.6 + lowpass(noise(d), 30) * 0.5) * env(int(SR * d), a=0.35, r=0.1), 0.5)
# Stunned: warbling descending chirps.
save("stun", seq([sweep(1400 - i * 250, 900 - i * 250, 0.09, square) * env(int(SR * 0.09), 0.005) for i in range(4)]), 0.35)
# Burn: crackling filtered noise.
d = 0.45
crackle = lowpass(noise(d), 4) * (rng.random(int(SR * d)) > 0.7)
save("burn", (crackle + lowpass(noise(d), 12) * 0.5) * env(int(SR * d), 0.02), 0.45)
# Chill: icy shimmer.
d = 0.5
sh = sum(np.sin(2 * np.pi * f * t(d) + 3 * np.sin(2 * np.pi * 7 * t(d))) for f in (1760, 2217, 2637))
save("chill", sh * env(int(SR * d), 0.01), 0.35)
# Shield: bright rising chord.
d = 0.4
save("shield", sum(sweep(f, f * 1.5, d) for f in (523, 659, 784)) * env(int(SR * d), 0.02), 0.4)
# Heal: soft ascending arpeggio.
save("heal", seq([tone(f, 0.11) * env(int(SR * 0.11), 0.01) for f in (523, 659, 784, 1047)]), 0.4)
# Ability: whoosh.
d = 0.32
save("ability", lowpass(noise(d), 6) * sweep(200, 1200, d) * env(int(SR * d), 0.08), 0.5)
# Relic proc: bell.
d = 0.7
save("relic", sum(np.sin(2 * np.pi * f * t(d)) * a for f, a in ((880, 1), (1760, 0.5), (2640, 0.25), (1210, 0.3))) * env(int(SR * d), 0.003), 0.45)
# Level up: major arpeggio.
save("level_up", seq([tone(f, 0.1, square) * env(int(SR * 0.1), 0.005) * 0.6 for f in (523, 659, 784)] + [tone(1047, 0.25, square) * env(int(SR * 0.25), 0.005) * 0.6]), 0.35)
# Unlock: short fanfare.
save("unlock", seq([tone(f, dd, square) * env(int(SR * dd), 0.005, r=0.03) for f, dd in ((392, 0.12), (523, 0.12), (659, 0.12), (784, 0.35))]), 0.33)
# Story card: low swelling chord.
d = 1.3
save("story", sum(np.sin(2 * np.pi * f * t(d)) for f in (110, 165, 220, 277)) * env(int(SR * d), a=0.5, r=0.5), 0.45)
# Defeat: descending tones.
save("defeat", seq([tone(f, 0.2, square) * env(int(SR * 0.2), 0.005) for f in (392, 330, 262, 196)]), 0.35)
# Boss intro: deep drum hit.
d = 0.8
save("boss", (sweep(120, 40, d) + lowpass(noise(d), 40) * 0.6) * env(int(SR * d), 0.002), 0.6)
print("ok", sorted(f for f in os.listdir(OUT) if f.startswith("gen_") and f.endswith(".wav")))
