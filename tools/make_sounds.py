"""Oyunun seslerini sentezler (kayit kullanilmaz, lisans sorunu yok).

Kullanim: python3 tools/make_sounds.py assets/sfx
Uretilenler: ortam.wav (ruzgar + kus + uzak sehir, dongu), adim1-4.wav, para.wav, firlat.wav, tik.wav, mutlu.wav
"""
import os
import sys
import wave

import numpy as np

OUT = sys.argv[1]
SR = 44100
rng = np.random.default_rng(5)


def save(name, x, peak=0.8):
    x = x / max(np.abs(x).max(), 1e-9) * peak
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    print(name, round(len(x) / SR, 2), 's')


def lowpass(x, hz):
    a = np.exp(-2 * np.pi * hz / SR)
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc = a * acc + (1 - a) * v
        y[i] = acc
    return y


def smooth_noise(n, hz):
    """Yavas degisen 0..1 egri."""
    k = max(2, int(n / SR * hz) + 2)
    pts = rng.random(k)
    return np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)


def chirp(dur, f0, f1, vib=0.0):
    t = np.arange(int(dur * SR)) / SR
    f = f0 + (f1 - f0) * (t / dur) ** 1.5 + vib * np.sin(2 * np.pi * 38 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.hanning(len(t)) ** 0.8


def ambience():
    n = SR * 24
    wind = lowpass(rng.standard_normal(n + SR), 420)[SR:]
    wind = wind / np.abs(wind).max() * (0.35 + 0.65 * smooth_noise(n, 0.25))
    leaves = rng.standard_normal(n) - lowpass(rng.standard_normal(n), 2500)
    leaves = lowpass(leaves, 7000) * 0.05 * smooth_noise(n, 0.4) ** 2
    city = lowpass(rng.standard_normal(n), 120)
    city = city / np.abs(city).max() * 0.25 * (0.6 + 0.4 * smooth_noise(n, 0.1))
    x = wind * 0.5 + leaves + city
    # Kus civiltilari: farkli turler icin farkli nota kaliplari
    t = 0.6
    while t < 22.5:
        kind = rng.integers(0, 3)
        vol = rng.uniform(0.05, 0.16)
        pos = t
        if kind == 0:                                  # hizli tekrarlayan civilti
            base = rng.uniform(3800, 5200)
            for _ in range(rng.integers(3, 7)):
                c = chirp(0.07, base * 1.25, base, 60) * vol
                i = int(pos * SR); x[i:i + len(c)] += c; pos += 0.11
        elif kind == 1:                                # iki notali otus
            base = rng.uniform(2400, 3200)
            for f0, f1, d in ((base, base * 1.3, 0.16), (base * 1.35, base * 1.05, 0.22)):
                c = chirp(d, f0, f1, 25) * vol
                i = int(pos * SR); x[i:i + len(c)] += c; pos += d + 0.05
        else:                                          # inen uzun islik
            base = rng.uniform(4200, 6000)
            c = chirp(0.3, base, base * 0.6, 90) * vol * 0.8
            i = int(pos * SR); x[i:i + len(c)] += c
            pos += 0.3
        t = pos + rng.uniform(0.5, 2.6)
    # Dikissiz dongu: son saniyeyi basa karistir
    f = SR
    fade = np.linspace(0, 1, f)
    x[:f] = x[:f] * fade + x[-f:] * (1 - fade)
    save('ortam', x[:-f], 0.5)


def footstep(seed):
    r = np.random.default_rng(seed)
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    noise = lowpass(r.standard_normal(n), 1500 + 600 * r.random())
    crunch = (r.standard_normal(n) - lowpass(r.standard_normal(n), 3000)) * 0.25
    env = np.exp(-t * 38) * np.minimum(t * 900, 1)
    thump = np.sin(2 * np.pi * (85 + 20 * r.random()) * t) * np.exp(-t * 55) * 0.5
    return (noise / np.abs(noise).max() + crunch) * env + thump


def main():
    os.makedirs(OUT, exist_ok=True)
    ambience()
    for i in range(4):
        save('adim%d' % (i + 1), footstep(20 + i), 0.55)
    t = np.arange(int(0.45 * SR)) / SR
    coin = (np.sin(2 * np.pi * 1318 * t) * (t < 0.08) + np.sin(2 * np.pi * 1976 * t) * (t >= 0.07)) * np.exp(-t * 9)
    coin += 0.3 * np.sin(2 * np.pi * 3952 * t) * np.exp(-t * 14) * (t >= 0.07)
    save('para', coin, 0.5)
    n = int(0.35 * SR); t = np.arange(n) / SR
    sweep = rng.standard_normal(n)
    whoosh = np.zeros(n); acc = 0.0
    for i in range(n):                                  # kesim frekansi yukselen suzgec
        a = np.exp(-2 * np.pi * (300 + 2600 * (i / n)) / SR)
        acc = a * acc + (1 - a) * sweep[i]; whoosh[i] = acc
    save('firlat', whoosh * np.sin(np.pi * t / t[-1]) ** 1.5, 0.6)
    t = np.arange(int(0.05 * SR)) / SR
    save('tik', np.sin(2 * np.pi * 880 * t) * np.exp(-t * 90), 0.35)
    t = np.arange(int(0.5 * SR)) / SR
    happy = sum(np.sin(2 * np.pi * f * np.maximum(t - d, 0)) * np.exp(-np.maximum(t - d, 0) * 10) * (t >= d)
                for f, d in ((784, 0.0), (988, 0.09), (1175, 0.18)))
    save('mutlu', happy, 0.45)


main()
