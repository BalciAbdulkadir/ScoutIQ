# icon_v1.jpeg'den Android adaptive ikon katmanlarını üretir.
#
# Android'de ikonun şeklini telefon belirler: Pixel'de daire, Samsung'da yuvarlatılmış kare, bazı markalarda
# başka şekiller. Bu yüzden ikona sabit bir çerçeve çizilmez:
#  - ikon_zemin.png    : tahta yeşili zemin, ikonun tamamını kaplar (maske hangi şekli keserse kessin boşluk kalmaz)
#  - ikon_on_katman.png: sadece tebeşir çizimi (FL, ok, top), zemini şeffaf; her maskede görünen güvenli alanın
#                        (108dp'nin ortadaki 66dp'lik dairesi) içinde ve tam ortada
#
# Kullanım: python ikon_katmanlari.py icon_v1.jpeg <çıktı klasörü>   (Pillow ve NumPy gerekir)
# Sonra: dart run flutter_launcher_icons
import sys
import numpy as np
from PIL import Image

kaynak, cikti = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(7)

im = np.asarray(Image.open(kaynak).convert('RGB')).astype(np.float32)
H, W, _ = im.shape
lum = im @ np.array([0.299, 0.587, 0.114], dtype=np.float32)

zemin_orta = np.median(im[200:260, 380:640].reshape(-1, 3), axis=0)
zemin_kenar = np.median(im[5:30, 5:30].reshape(-1, 3), axis=0)

# Tebeşir: zeminden belirgin açık pikseller. Kare tebeşir çerçeve dışarıda kalsın diye sadece iç bölgeye bakılır.
zemin_lum = float(zemin_orta @ np.array([0.299, 0.587, 0.114]))
alfa = np.clip((lum - (zemin_lum + 25)) / 70.0, 0, 1)
ic = np.zeros_like(alfa)
ic[130:H - 130, 130:W - 130] = 1
alfa *= ic

ys, xs = np.where(alfa > 0.5)
pay = 12
x0, x1 = max(xs.min() - pay, 0), min(xs.max() + pay, W - 1)
y0, y1 = max(ys.min() - pay, 0), min(ys.max() + pay, H - 1)
icerik = im[y0:y1 + 1, x0:x1 + 1]
icerik_alfa = alfa[y0:y1 + 1, x0:x1 + 1]

# Rengi zeminden arındır: piksel = zemin*(1-a) + renk*a
a = np.maximum(icerik_alfa, 1e-3)[..., None]
icerik_renk = np.clip((icerik - zemin_orta * (1 - a)) / a, 0, 255)

N = 1024
merkez = (N - 1) / 2
guvenli_yaricap = N * 66 / 108 / 2

# Ön katman: çizim güvenli dairenin içine sığacak şekilde ölçeklenir, tam ortaya konur.
# Kutunun köşeleri boş olduğu için yarı köşegen güvenli yarıçapı biraz aşabilir.
h, w = icerik_alfa.shape
olcek = guvenli_yaricap * 0.70 * 1.12 / (np.hypot(w, h) / 2)
yw, yh = int(w * olcek), int(h * olcek)
rgba = np.dstack([icerik_renk, icerik_alfa * 255]).astype(np.uint8)
kucuk = Image.fromarray(rgba, 'RGBA').resize((yw, yh), Image.LANCZOS)
on = Image.new('RGBA', (N, N), (0, 0, 0, 0))
on.paste(kucuk, (int(round(merkez - yw / 2)), int(round(merkez - yh / 2))))
on.save(f'{cikti}/ikon_on_katman.png', optimize=True)

# Güvenli dairenin dışına taşan çizim var mı
on_alfa = np.asarray(on)[..., 3]
yy, xx = np.mgrid[0:N, 0:N]
uzaklik = np.sqrt((xx - merkez) ** 2 + (yy - merkez) ** 2)
tasan = int(((on_alfa > 40) & (uzaklik > guvenli_yaricap)).sum())
print('olcek', round(olcek, 3), 'cizim', yw, yh, 'guvenli alan disina tasan piksel', tasan)

# Zemin: merkezden kenara hafif koyulaşan tahta yeşili ve ince tebeşir tozu
t = np.clip(uzaklik / (N * 0.62), 0, 1)[..., None]
zemin = zemin_orta * (1 - t) + zemin_kenar * t
zemin += rng.normal(0, 2.0, (N, N, 1))
Image.fromarray(np.clip(zemin, 0, 255).astype(np.uint8)).save(f'{cikti}/ikon_zemin.png', optimize=True)
