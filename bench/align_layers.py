# Положение и масштаб слоёв леса и замка относительно фона: python bench/align_layers.py (из корня проекта; нужны numpy, scipy, pillow).
# Слой (прозрачный PNG) уменьшается в s раз (усреднение BOX) и ищется на фоне: перебор масштаба, сдвиг — минимум средней
# квадратичной ошибки цвета по непрозрачным пикселям слоя (маскированная SSD через FFT, сразу по всем сдвигам).
# Грубо (фон и слой уменьшены в 4 раза, шаг масштаба 0.05), затем точно (полный размер, сдвиг — целый тексель фона).
# Ошибка — RMS по каналам 0..255; совпадение годно, если ошибка <= MAX_ERR. Печатает масштаб, сдвиг в текселях фона и в
# пикселях поля (BG_SCALE, BG_OFFSET из main.gd), ошибку и её рост при сдвиге слоя на SHIFT_PROFILE текселей;
# пишет bench/align_diag.png (не коммитится): фон, слои на 50%, контуры слоёв пурпурным.
import io
import re
import sys

import numpy as np
from PIL import Image
from scipy import fft as sfft

MAX_ERR = 50.0
SHIFT_PROFILE = (1, 3, 8, 20)
BG = 'art/castle_map.png'
LAYERS = [  # имя, файл, грубый перебор масштаба (от, до, шаг), точный шаг
    ('лес', 'art/trees_lay.png', (0.3, 3.0, 0.05), 0.002),
    ('замок', 'art/castle_lay_two.png', (0.3, 3.0, 0.05), 0.002),
]


def rgba(path):
    return Image.open(path).convert('RGBA')


def search(L, B, scales, down=1):
    # L — слой (PIL RGBA), B — фон (PIL RGBA), масштаб s — в текселях фона; оба уменьшены в down раз.
    # Результат по возрастанию ошибки: [(ошибка, s, dx, dy, карта ошибок, (ix, iy) минимума в карте, pad)].
    Bd = np.asarray(B.resize((B.width // down, B.height // down), Image.BOX))[..., :3].astype(np.float64)
    sized = [(s, max(1, round(L.width * s / down)), max(1, round(L.height * s / down))) for s in scales]
    ph, pw = max(h for _, _, h in sized), max(w for _, w, _ in sized)   # слой может выходить за край фона
    shape = (Bd.shape[0] + 2 * ph, Bd.shape[1] + 2 * pw)
    fs = [sfft.next_fast_len(n, True) for n in shape]
    V = np.zeros(shape)
    V[ph:ph + Bd.shape[0], pw:pw + Bd.shape[1]] = 1
    Bp = np.zeros(shape + (3,))
    Bp[ph:ph + Bd.shape[0], pw:pw + Bd.shape[1]] = Bd
    F = lambda a: sfft.rfft2(a, fs, workers=-1)
    fV, fB2, fB = F(V), F((Bp ** 2).sum(-1)), [F(Bp[..., c]) for c in range(3)]
    # корреляция через FFT: сумма по пикселям слоя K[i, j] * A[y + i, x + j] = irfft(F(A) * conj(F(K))); без заворота при y <= H + ph
    corr = lambda fa: sfft.irfft2(fa, fs, workers=-1)[:shape[0] - ph + 1, :shape[1] - pw + 1]
    res = []
    for s, nw, nh in sized:
        Ls = np.asarray(L.resize((nw, nh), Image.BOX)).astype(np.float64)
        m = (Ls[..., 3] > 250).astype(np.float64)
        if m.sum() < 50:
            continue
        fm = np.conj(F(m))
        cover = corr(fV * fm)
        acc = fB2 * fm + fV * np.conj(F(m * (Ls[..., :3] ** 2).sum(-1)))
        for c in range(3):
            acc -= 2 * fB[c] * np.conj(F(m * Ls[..., c]))
        ssd = corr(acc)
        err = np.where(cover >= 0.9 * m.sum(), np.sqrt(np.maximum(ssd, 0) / np.maximum(cover, 1) / 3), np.inf)
        iy, ix = np.unravel_index(np.argmin(err), err.shape)
        res.append((err[iy, ix], s, (ix - pw) * down, (iy - ph) * down, err, (ix, iy)))
    res.sort(key=lambda r: r[0])
    return res


def main_consts():
    src = io.open('scripts/main.gd', encoding='utf-8').read()
    scale = eval(re.search(r'^const BG_SCALE := (.+?)(?:\s+#|$)', src, re.M).group(1))
    off = re.search(r'^const BG_OFFSET := Vector2\((-?[\d.]+), (-?[\d.]+)\)', src, re.M)
    return scale, (float(off.group(1)), float(off.group(2)))


def main():
    B = rgba(BG)
    bg_scale, bg_off = main_consts()
    diag = np.asarray(B).astype(np.float64)
    bad = 0
    for name, path, (smin, smax, step), fine in LAYERS:
        L = rgba(path)
        coarse = search(L, B, np.arange(smin, smax + 1e-9, step), down=4)
        s0 = coarse[0][1]
        err, s, dx, dy, emap, (ix, iy) = search(L, B, np.arange(s0 - step * 0.6, s0 + step * 0.6 + 1e-9, fine))[0]
        ok = err <= MAX_ERR
        bad += not ok
        # насколько выражен минимум: ошибка при сдвиге слоя на d текселей (худшее и лучшее из 4 направлений)
        prof = ' '.join('%d: %.1f' % (d, min(emap[iy + a, ix + b] for a, b in ((-d, 0), (d, 0), (0, -d), (0, d))))
                        for d in SHIFT_PROFILE)
        print('%s %s %dx%d: масштаб %.3f, сдвиг (%d, %d) текселей фона; на поле: position (%.2f, %.2f), scale %.4f; '
              'ошибка %.2f (порог %.0f) — %s; при сдвиге на d текселей (лучшее направление) %s' % (
                  name, path, L.width, L.height, s, dx, dy, bg_off[0] + dx * bg_scale, bg_off[1] + dy * bg_scale, s * bg_scale,
                  err, MAX_ERR, 'ок' if ok else 'ПЛОХО', prof))
        # диагностика: слой на 50% поверх фона, контур пурпурным
        Ls = L.resize((round(L.width * s), round(L.height * s)), Image.NEAREST)
        can = Image.new('RGBA', B.size, (0, 0, 0, 0))
        can.paste(Ls, (round(dx), round(dy)))
        c = np.asarray(can).astype(np.float64)
        a = c[..., 3] > 127
        diag = np.where(a[..., None], 0.5 * diag + 0.5 * c, diag)
        edge = (a ^ np.roll(a, 1, 0)) | (a ^ np.roll(a, 1, 1))
        diag[edge] = (255, 0, 255, 255)
    Image.fromarray(diag.astype(np.uint8)).save('bench/align_diag.png')
    print('ok' if bad == 0 else 'ПЛОХО: %d' % bad)
    return bad


if __name__ == '__main__':
    sys.exit(main())
