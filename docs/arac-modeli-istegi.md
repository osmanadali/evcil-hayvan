# Araç içi görünüm için gereken modeller

Sürerken görmek istediğin ekran (ön cam ve yol, direksiyon ve iki el, gösterge paneli, navigasyon ekranı,
aynalar) için oyuna iki model lazım. İkisini de `assets/vehicles/` klasörüne koyman yeterli; oyun dosyayı
görünce kendiliğinden kullanır. Dosya yoksa şimdiki araba (kodla çizilmiş iç mekân) kullanılmaya devam eder.

## 1. İç mekânlı araba — `assets/vehicles/araba.glb`

- Biçim: **GLB** (glTF ikili), dokular dosyanın içinde gömülü.
- **İç mekânı olan** bir araba olmalı (koltuklar, ön panel, direksiyon modellenmiş). "Low poly" ya da
  "game ready" + "with interior" diye aratılan modeller uygundur. Yalnız dış kabuğu olan model işe yaramaz.
- Ölçek **metre** (araba yaklaşık 4 m uzun, 1,7 m geniş), arabanın **önü −Z** yönüne bakmalı,
  tekerlekler yere (y = 0) basmalı, direksiyon **solda**.
- Üçgen sayısı: en çok 150 bin (daha fazlası oyunu yavaşlatır).
- Araba **tek parça olmamalı**. Aşağıdaki parçalar ayrı nesneler olmalı ve adları şu sözcüklerle başlamalı
  (büyük/küçük harf fark etmez):

| Parça | Nesne adı | Not |
|---|---|---|
| Gövde | `Govde` | Kaput, tavan, çamurluklar, bagaj |
| Sürücü kapısı | `Kapi_OnSol` | Binerken bu kapı açılır |
| Diğer kapılar | `Kapi_OnSag`, `Kapi_ArkaSol`, `Kapi_ArkaSag` | |
| Direksiyon | `Direksiyon` | Tek başına dönebilmeli (panelden ayrı) |
| Ön panel | `OnPanel` | Torpido, havalandırmalar, orta konsol |
| Koltuklar | `Koltuklar` | Ön ve arka koltuklar |
| Camlar | `Cam` ya da malzeme adı `Cam` | Camlar **ayrı malzeme** olmalı; oyun onu saydam yapar |
| İç dikiz aynası | `Ayna_Ic` | Oyun üstüne arkayı gösteren görüntü koyar |
| Yan aynalar | `Ayna_Sol`, `Ayna_Sag` | |
| Tekerler | `Teker_OnSol`, `Teker_OnSag`, `Teker_ArkaSol`, `Teker_ArkaSag` | Her biri ayrı; dönerler |
| Gösterge ekranı (isteğe bağlı) | `Ekran_Gosterge` | Düz bir yüzey; oyun hız, devir ve yakıtı buraya çizer |
| Navigasyon ekranı (isteğe bağlı) | `Ekran_Navigasyon` | Düz bir yüzey; oyun haritayı ve rotayı buraya çizer |

- Gerçek marka logosu olmasın (ya da silinmiş olsun).

## 2. Birinci şahıs kol / el modeli — `assets/vehicles/kollar.glb` (isteğe bağlı)

- İki ön kol ve el; eller direksiyonu **saat 10 ve 2** konumunda tutar biçimde.
- Ölçek metre, **−Z ileri**; modelin başlangıç noktası (0, 0, 0) **sürücünün göz hizası** olmalı
  (eller gözün yaklaşık 35 cm aşağısında, 50 cm önünde).
- Bu dosya yoksa oyun karakterin kendi kollarını gösterir (şimdi olduğu gibi).

## Oyun bu modelle ne yapar

- Camları saydam yapar, sürücü kapısını menteşesinden açar, tekerleri ve direksiyonu döndürür.
- Kamerayı sürücü koltuğuna, göz hizasına koyar (direksiyonun yerine göre hesaplar).
- Aynalara arkayı gösteren görüntüyü, ekranlara gösterge ve navigasyonu yerleştirir.
- Ölçek ya da yön yanlışsa düzeltmeye çalışır (araba 4 m'ye getirilir, direksiyon öne gelecek biçimde
  çevrilir); yine de yukarıdaki gibi hazırlanmış model en iyi sonucu verir.

Not: Bu yol henüz gerçek bir modelle denenmedi; modeli koyduktan sonra oyunda bakıp küçük ayar gerekebilir.
