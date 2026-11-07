# icon_v1.jpeg'den yuvarlak ikon üretir:
#  - kare tebeşir çerçeveyi atar, içerikteki tebeşir çizimini (FL, ok, top) alır ve tam ortalar
#  - koyu yeşil tahta zemini üstüne tebeşirle çizilmiş bir daire ekler
# Çıktılar:
#  ikon_on_katman.png : Android 8+ adaptive ikon ön katmanı (1024, opak). Daire, launcher maskesine (108dp'nin 72dp'si) tam oturur.
#  ikon_yuvarlak.png  : Eski Android sürümleri için daire ikon (1024, dairenin dışı şeffaf).
import sys
import numpy as np
from PIL import Image, ImageFilter

kaynak, cikti_klasoru = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(7)

im = np.asarray(Image.open(kaynak).convert('RGB')).astype(np.float32)
H, W, _ = im.shape
lum = im @ np.array([0.299, 0.587, 0.114], dtype=np.float32)

# Tahtanın zemin renkleri: merkeze yakın ve kenara yakın
zemin_orta = np.median(im[200:260, 380:640].reshape(-1, 3), axis=0)
zemin_kenar = np.median(im[5:30, 5:30].reshape(-1, 3), axis=0)

# Tebeşir: zeminden belirgin şekilde açık pikseller. Kare çerçeveyi dışarıda bırakmak için iç bölgeye bakılır.
zemin_lum = float(zemin_orta @ np.array([0.299, 0.587, 0.114]))
alfa = np.clip((lum - (zemin_lum + 25)) / 70.0, 0, 1)
ic = np.zeros_like(alfa)
ic[130:H - 130, 130:W - 130] = 1
alfa *= ic

ys, xs = np.where(alfa > 0.5)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
print('icerik kutusu', x0, y0, x1, y1)
pay = 12
x0, y0, x1, y1 = max(x0 - pay, 0), max(y0 - pay, 0), min(x1 + pay, W - 1), min(y1 + pay, H - 1)
icerik = im[y0:y1 + 1, x0:x1 + 1]
icerik_alfa = alfa[y0:y1 + 1, x0:x1 + 1]

N = 1024
merkez = (N - 1) / 2
R = N * 72 / 108 / 2  # launcher maskesinin yarıçapı

# Zemin: merkezden kenara hafif koyulaşan tahta yeşili ve ince tebeşir tozu
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
uzaklik = np.sqrt((xx - merkez) ** 2 + (yy - merkez) ** 2)
t = np.clip(uzaklik / (R * 1.05), 0, 1)[..., None]
zemin = zemin_orta * (1 - t) + zemin_kenar * t
zemin += rng.normal(0, 2.0, (N, N, 1)).astype(np.float32)

# İçerik: dairenin içine sığacak şekilde ölçeklenir ve tam ortaya konur
h, w = icerik_alfa.shape
sigma_yaricapi = R * 0.80
olcek = sigma_yaricapi / (np.hypot(w, h) / 2) * 1.12  # köşeler boş olduğu için biraz büyütülür
yeni_w, yeni_h = int(w * olcek), int(h * olcek)
icerik_r = np.asarray(Image.fromarray(icerik.astype(np.uint8)).resize((yeni_w, yeni_h), Image.LANCZOS)).astype(np.float32)
alfa_r = np.asarray(Image.fromarray((icerik_alfa * 255).astype(np.uint8)).resize((yeni_w, yeni_h), Image.LANCZOS)).astype(np.float32) / 255
ox, oy = int(round(merkez - yeni_w / 2)), int(round(merkez - yeni_h / 2))
bolge = zemin[oy:oy + yeni_h, ox:ox + yeni_w]
a = alfa_r[..., None]
zemin[oy:oy + yeni_h, ox:ox + yeni_w] = bolge * (1 - a) + icerik_r * a

# Tebeşir daire: kare çerçevenin rengiyle, kenarları pürüzlü
cerceve_rengi = np.array([170, 190, 178], dtype=np.float32)
halka_r = R * 0.89
kalinlik = 26.0
gurultu = np.asarray(Image.fromarray((rng.random((N, N)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255
sapma = (gurultu - 0.5) * 9
halka = np.clip(1 - np.abs(uzaklik + sapma - halka_r) / (kalinlik / 2), 0, 1)
halka *= np.clip(0.75 + gurultu * 0.5, 0, 1)
halka = halka[..., None]
zemin = zemin * (1 - halka) + cerceve_rengi * halka

on_katman = np.clip(zemin, 0, 255).astype(np.uint8)
Image.fromarray(on_katman).save(f'{cikti_klasoru}/ikon_on_katman.png')

# Eski Android: daire bütün görsele yayılır, dışı şeffaf
k0 = int(round(merkez - R))
kare = Image.fromarray(on_katman).crop((k0, k0, k0 + int(2 * R), k0 + int(2 * R))).resize((N, N), Image.LANCZOS)
maske_yy, maske_xx = np.mgrid[0:N, 0:N]
mu = np.sqrt((maske_xx - (N - 1) / 2) ** 2 + (maske_yy - (N - 1) / 2) ** 2)
maske = np.clip((N / 2 - mu) * 1.5, 0, 1) * 255
yuvarlak = np.dstack([np.asarray(kare), maske.astype(np.uint8)])
Image.fromarray(yuvarlak, 'RGBA').save(f'{cikti_klasoru}/ikon_yuvarlak.png')
print('olcek', round(olcek, 3), 'icerik', yeni_w, yeni_h)
