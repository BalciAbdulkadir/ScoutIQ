"""icon_v1.jpeg'den Android adaptive icon katmanlarını üretir.

Kullanım (mobile/ içinden):
  python tool/adaptive_ikon.py assets/icons/icon_v1.jpeg       assets/icons/icon_adaptive_arka.png assets/icons/icon_adaptive_on.png
  dart run flutter_launcher_icons

arka plan : görselin yeşil gradyanı (tebeşir çerçevesiz), 1024x1024
ön plan   : çerçevenin içindeki logo, kenarları saydamlaşarak arka plana karışır
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

kaynak, arka_yol, on_yol = sys.argv[1:4]
im = np.asarray(Image.open(kaynak).convert("RGB"), dtype=np.float64)
H, W, _ = im.shape

# 1) Gradyanı tebeşirsiz noktalardan 2. derece polinomla modelle.
yy, xx = np.mgrid[0:H, 0:W]
x, y = xx / W, yy / H
parlaklik = im.mean(axis=2)
# Tebeşir açık renkli; düz zemin koyu. Logo bölgesini ve çerçeve çizgisini dışarıda bırak.
zemin = parlaklik < 80
zemin &= ~((xx > 150) & (xx < 870) & (yy > 280) & (yy < 770))
ornek = zemin[::4, ::4]
X = np.stack([np.ones_like(x), x, y, x * x, y * y, x * y], axis=-1)
A = X[::4, ::4][ornek]
TUVAL = 1024
# Ön plan bu oranla küçültülecek (aşağıya bakınız); arka plan gradyanı da aynı eşlemeyle çizilir
# ki ön planın saydamlaşan kenarı altındaki renkle birebir örtüşsün.
olcek = (33 / 108 * TUVAL) / 420
mx = (W / 2 + (xx - TUVAL / 2) / olcek) / W
my = (H / 2 + (yy - TUVAL / 2) / olcek) / H
Xm = np.stack([np.ones_like(mx), mx, my, mx * mx, my * my, mx * my], axis=-1)
arka = np.empty_like(im)
for k in range(3):
    b = im[::4, ::4, k][ornek]
    katsayi, *_ = np.linalg.lstsq(A, b, rcond=None)
    arka[..., k] = Xm @ katsayi
arka_img = Image.fromarray(np.clip(arka, 0, 255).astype(np.uint8))
arka_img.save(arka_yol)

# 2) Ön plan: yalnızca tebeşir (logo + top + ok). Yeşil zemin saydamlaştırılır, böylece
# ön plan hangi gradyanın üstüne gelirse gelsin ek yeri oluşmaz.
zemin_orj = np.empty_like(im)
for k in range(3):
    b = im[::4, ::4, k][ornek]
    katsayi, *_ = np.linalg.lstsq(A, b, rcond=None)
    zemin_orj[..., k] = X @ katsayi
TEBESIR = 232.0  # tebeşirin en parlak kanal değeri (beyaz ve sarı için ~aynı)
zmax = zemin_orj.max(axis=2)
alfa = np.clip((im.max(axis=2) - zmax - 8) / (TEBESIR - zmax - 8), 0, 1)
# Renk: piksel = a*tebeşir + (1-a)*zemin  =>  tebeşir = (piksel - (1-a)*zemin) / a
a3 = np.maximum(alfa, 1e-3)[..., None]
renk = np.clip((im - (1 - a3) * zemin_orj) / a3, 0, 255)
# Tebeşir çerçeveyi dışarıda bırak: yalnızca iç bölge.
x0, y0, x1, y1 = 135, 135, 889, 889
alfa[:y0, :] = alfa[y1:, :] = 0
alfa[:, :x0] = alfa[:, x1:] = 0
kirp = np.dstack([renk, alfa * 255])[y0:y1, x0:x1]
h, w = kirp.shape[:2]
on = kirp.astype(np.uint8)

# Adaptive icon tuvali 108dp; görünür güvenli alan merkezdeki 66dp daire.
# Logonun en uzak noktası merkezden ~420px; bunu ~33dp'ye sığdıracak ölçek.
yeni = round(w * olcek)
on_img = Image.fromarray(on).resize((yeni, yeni), Image.LANCZOS)
tuval = Image.new("RGBA", (TUVAL, TUVAL), (0, 0, 0, 0))
ofs = (TUVAL - yeni) // 2
tuval.paste(on_img, (ofs, ofs), on_img)
tuval.save(on_yol)
print("arka:", arka_img.size, "on:", tuval.size, "logo boyu:", yeni)
