"""Ev ici dokularini uretir (assets/home/): fotograflardaki desenlere benzer, telif sorunu olmayan cizimler.

Kullanim: python3 tools/make_home_textures.py
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'home')
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(3)


def noise(w, h, amt, blur=1.0):
    a = np.random.default_rng(rnd.randint(0, 9999)).normal(0, amt, (h, w))
    return np.asarray(Image.fromarray(np.uint8(np.clip(a + 128, 0, 255))).filter(ImageFilter.GaussianBlur(blur)), np.float32) - 128


def save(name, im):
    im.convert('RGB').save(os.path.join(OUT, name), quality=92)
    print(name, im.size)


def encaustic():
    """Siyah-beyaz cimento karo (WC ve banyo zemini): 2x2 karo, her biri ortada dort yaprakli cicek."""
    S = 512
    im = Image.new('RGB', (S, S), (238, 236, 230))
    d = ImageDraw.Draw(im)
    T = S // 2
    ink = (24, 24, 26)
    for ty in range(2):
        for tx in range(2):
            ox, oy = tx * T, ty * T
            c = (ox + T / 2, oy + T / 2)
            for k in range(4):                        # dort buyuk yaprak
                a = k * math.pi / 2
                pts = []
                for t in np.linspace(0, 1, 24):
                    rr = T * 0.42 * math.sin(t * math.pi) ** 0.8
                    ang = a + (t - 0.5) * 0.9
                    pts.append((c[0] + math.cos(ang) * (T * 0.08 + rr), c[1] + math.sin(ang) * (T * 0.08 + rr)))
                d.polygon(pts, fill=ink)
                inner = [(c[0] + (x - c[0]) * 0.45, c[1] + (y - c[1]) * 0.45) for x, y in pts]
                d.polygon(inner, fill=(238, 236, 230))
            for k in range(4):                        # koselerde ceyrek yapraklar
                cx, cy = ox + (k % 2) * T, oy + (k // 2) * T
                a0 = math.atan2(c[1] - cy, c[0] - cx)
                pts = [(cx, cy)]
                for t in np.linspace(-0.55, 0.55, 12):
                    pts.append((cx + math.cos(a0 + t) * T * 0.3, cy + math.sin(a0 + t) * T * 0.3))
                d.polygon(pts, fill=ink)
            d.regular_polygon((c[0], c[1], T * 0.07), 4, rotation=45, fill=ink)
            d.rectangle([ox, oy, ox + T - 1, oy + T - 1], outline=(200, 198, 192), width=2)
    a = np.asarray(im, np.float32) + noise(S, S, 10, 1.2)[..., None]
    save('karo_desen.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))


def basket_tile():
    """Koridorun gri-bej sepet orgu karolari: 4 cubuklu kareler sirayla yatay/dikey."""
    S = 512
    im = Image.new('RGB', (S, S), (196, 190, 188))
    d = ImageDraw.Draw(im)
    n = 4
    T = S // n
    for j in range(n):
        for i in range(n):
            ox, oy = i * T, j * T
            vertical = (i + j) % 2 == 0
            for k in range(3):
                shade = 205 + rnd.randint(-10, 8)
                col = (shade, shade - 6, shade - 4)
                if vertical:
                    d.rectangle([ox + k * T / 3 + 2, oy + 2, ox + (k + 1) * T / 3 - 2, oy + T - 2], fill=col)
                else:
                    d.rectangle([ox + 2, oy + k * T / 3 + 2, ox + T - 2, oy + (k + 1) * T / 3 - 2], fill=col)
    a = np.asarray(im, np.float32) + noise(S, S, 7, 0.8)[..., None]
    save('karo_koridor.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))


def runner():
    """Koridor yolluk: krem zemin, siyah-gri dalga cizgileri."""
    W, H = 256, 1024
    im = Image.new('RGB', (W, H), (232, 226, 210))
    d = ImageDraw.Draw(im)
    for row in range(0, H + 60, 52):
        for k, col in enumerate([(30, 30, 32), (120, 130, 140)]):
            pts = [(x, row + k * 14 + 9 * math.sin(x / W * math.tau * 2 + row)) for x in range(-10, W + 10, 6)]
            d.line(pts, fill=col, width=6 if k == 0 else 4)
    d.rectangle([0, 0, W - 1, H - 1], outline=(214, 206, 188), width=10)
    a = np.asarray(im, np.float32) + noise(W, H, 9, 1.0)[..., None]
    save('yolluk.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))


def shag():
    """Salon tuylu hali: krem zemin, kahve ve bej kalin dalgalar."""
    S = 768
    a = np.zeros((S, S, 3), np.float32)
    yy, xx = np.mgrid[0:S, 0:S] / S
    band = np.sin((xx * 2.2 + 0.35 * np.sin(yy * 5.0)) * math.pi * 2)
    base = np.array([226, 218, 204], np.float32)
    dark = np.array([74, 52, 40], np.float32)
    mid = np.array([150, 118, 90], np.float32)
    w1 = (band > 0.55).astype(np.float32)[..., None]
    w2 = ((band < -0.6)).astype(np.float32)[..., None]
    a[:] = base
    a = a * (1 - w1) + dark * w1
    a = a * (1 - w2) + mid * w2
    fib = noise(S, S, 40, 0.6)
    a += fib[..., None] * 0.6
    save('hali_salon.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))).filter(ImageFilter.GaussianBlur(1.2)))


def hall_rug():
    """Salona giris hali: acik gri, mor-kahve cizgi ve daire motifleri."""
    W, H = 512, 768
    im = Image.new('RGB', (W, H), (214, 206, 204))
    d = ImageDraw.Draw(im)
    col = (122, 96, 98)
    for k in range(18):
        x = rnd.randint(20, W - 60)
        y = rnd.randint(20, H - 40)
        if rnd.random() < 0.5:
            L = rnd.randint(60, 200)
            d.line([(x, y), (x + L, y)], fill=col, width=7)
            for t in range(3):
                d.line([(x + 15 + t * 22, y - 18), (x + 15 + t * 22, y + 18)], fill=col, width=5)
        else:
            L = rnd.randint(60, 200)
            d.line([(x, y), (x, y + L)], fill=col, width=7)
        d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=col)
    a = np.asarray(im, np.float32) + noise(W, H, 8, 1.0)[..., None]
    save('hali_giris.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))


def oriental():
    """Yatak odasi kilimi: kahve-bordo zemin, ince desenler."""
    W, H = 384, 1024
    a = np.zeros((H, W, 3), np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    a[:] = (112, 76, 56)
    pat = (np.sin(xx / 7.0) * np.sin(yy / 7.0) > 0.35)
    a[pat] = (186, 160, 128)
    border = (xx < 34) | (xx > W - 34) | (yy < 34) | (yy > H - 34)
    a[border] = (70, 46, 36)
    a[(xx > 40) & (xx < 46) | (xx > W - 46) & (xx < W - 40)] = (196, 170, 130)
    a += noise(W, H, 10, 0.8)[..., None]
    save('kilim.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))


def armchair_fabric():
    """Berjer kumasi: lacivert zemin, gri-mor yaprak desenleri."""
    S = 512
    im = Image.new('RGB', (S, S), (44, 46, 82))
    d = ImageDraw.Draw(im)
    for k in range(70):
        x, y = rnd.randint(0, S), rnd.randint(0, S)
        r = rnd.randint(10, 34)
        a = rnd.random() * math.pi
        col = rnd.choice([(150, 150, 180), (120, 110, 150), (190, 186, 200), (90, 100, 140)])
        pts = [(x + math.cos(a + t) * r * (1.0 if i % 2 == 0 else 0.35), y + math.sin(a + t) * r * (1.0 if i % 2 == 0 else 0.35))
               for i, t in enumerate(np.linspace(0, math.tau, 9)[:-1])]
        d.polygon(pts, fill=col)
    arr = np.asarray(im.filter(ImageFilter.GaussianBlur(1.0)), np.float32) + noise(S, S, 10, 0.6)[..., None]
    save('berjer.jpg', Image.fromarray(np.uint8(np.clip(arr, 0, 255))))


def car_poster():
    """Duvardaki tablo: gri tonlu fonda siyah, uzun kaputlu klasik spor araba silueti (marka yok)."""
    W, H = 768, 300
    im = Image.new('RGB', (W, H), (200, 202, 204))
    d = ImageDraw.Draw(im)
    for y in range(H):
        g = int(150 + 70 * (y / H))
        d.line([(0, y), (W, y)], fill=(g, g, g + 2))
    d.rectangle([0, H * 0.72, W, H], fill=(120, 122, 124))
    body = [(150, 205), (170, 168), (300, 156), (360, 120), (470, 118), (540, 150), (640, 160), (660, 200), (640, 214), (170, 216)]
    d.polygon(body, fill=(18, 18, 20))
    d.polygon([(372, 126), (462, 124), (520, 150), (350, 152)], fill=(70, 74, 80))
    for cx in (240, 560):
        d.ellipse([cx - 34, 180, cx + 34, 248], fill=(10, 10, 10))
        d.ellipse([cx - 18, 196, cx + 18, 232], fill=(150, 150, 154))
    d.line([(180, 186), (630, 186)], fill=(70, 70, 74), width=2)
    save('tablo.jpg', im.filter(ImageFilter.GaussianBlur(0.8)))


def plaster():
    """Duvar boyasi: hafif dalgali krem."""
    S = 512
    a = np.zeros((S, S, 3), np.float32)
    a[:] = (240, 234, 220)
    a += noise(S, S, 14, 3.0)[..., None] * 0.5 + noise(S, S, 8, 0.7)[..., None] * 0.35
    save('siva.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))


def mint_tile():
    """WC ve banyo duvar karosu: mint yesili kare karolar, beyaz derz."""
    S = 512
    a = np.zeros((S, S, 3), np.float32)
    a[:] = (176, 214, 204)
    yy, xx = np.mgrid[0:S, 0:S]
    a[(xx % 128 < 3) | (yy % 128 < 3)] = (232, 236, 232)
    a += noise(S, S, 6, 1.5)[..., None]
    save('karo_mint.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))
    a[:] = (242, 242, 238)
    a[(xx % 128 < 3) | (yy % 128 < 3)] = (210, 210, 206)
    a += noise(S, S, 4, 1.5)[..., None]
    save('karo_beyaz.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))))


def city_night():
    """Balkondan uzak sehir isiklari (gece) icin dolgu gorseli: ufuk cizgisi ve isik noktalari."""
    W, H = 2048, 512
    a = np.zeros((H, W, 3), np.float32)
    for y in range(H):
        a[y] = (40 + 30 * y / H, 34 + 20 * y / H, 40 + 10 * y / H)
    r = np.random.default_rng(7)
    sky = int(H * 0.42)
    hills = (sky + 30 * np.sin(np.arange(W) / 140.0) + 18 * np.sin(np.arange(W) / 47.0)).astype(int)
    for x in range(W):
        a[hills[x]:, x] = (14, 12, 14)
    for _ in range(9000):
        x = r.integers(0, W)
        y = r.integers(hills[x], H)
        c = r.choice([(255, 210, 140), (255, 240, 220), (180, 220, 255), (255, 170, 90)])
        a[y, x] = c
        if r.random() < 0.3 and y + 1 < H:
            a[y + 1, x] = np.array(c) * 0.6
    save('sehir_gece.jpg', Image.fromarray(np.uint8(np.clip(a, 0, 255))).filter(ImageFilter.GaussianBlur(0.6)))


for f in (encaustic, basket_tile, runner, shag, hall_rug, oriental, armchair_fabric, car_poster, plaster, mint_tile, city_night):
    f()
