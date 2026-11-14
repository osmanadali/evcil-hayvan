# Özgün şehir planı

Durum: özellik paketi (tur 2 + paralel işler) bittikten sonra başlanacak.

## Hedef
Gerçek OpenStreetMap Keçiören haritası yerine oyuna göre tasarlanmış, hayali bir şehir.
Keçiören (Subayevleri, Altınpark gölü, Arif Sokak'taki ev, Çınaraltı) bu şehrin içinde
"eski mahalle" olarak yaşamaya devam eder. Ayrıca şehirlerarası yolla gidilen ikinci bir şehir var.

## 1. Ana şehir (adı sonra seçilecek)
- Şehir üretici: `tools/city_gen.py`, `assets/city.json` ile AYNI formatta veri üretir
  (roads, buildings, pois, parks, water, signals, spots), böylece world.gd, trafik,
  navigasyon, mini harita, metro, dükkânlar değişmeden çalışır.
- Bölgeler:
  - Keçiören (mevcut OSM verisinden kesilip yerleştirilir: park, göl, ev, Subayevleri sokakları)
  - Merkez / çarşı (Kızılay benzeri meydan, işhanları, kalabalık)
  - Yeni siteler bölgesi (yüksek bloklar, AVM)
  - Eski şehir / kale semti (dar sokaklar, taş evler)
  - Sanayi ve otogar bölgesi
  - Çevre yolu / otoyol bağlantısı
- Metro hattı birkaç bölgeyi bağlar (mevcut metro_ride sistemi).
- Sabit noktalar (spot: baslangic, kafe, petshop, oyun_alani, cardak, cesme, piknik,
  dondurmaci, bahce; metro girişleri; ev) üreticide isimli olarak tanımlanır.

## 2. Şehirlerarası yolculuk
- Otogar: peronlar, bilet gişeleri, firma tabelaları (uydurma firma adları), bekleme salonu, çay ocağı.
- Telefonda "Otobüs Bileti" uygulaması: sefer listesi (saat, firma, koltuk seçimi, fiyat).
- Bilet saatinde peronda olmazsan otobüs kalkar, bilet yanar (iade yok ya da kesintili iade).
- Yolculuk: otobüs içi yolcu kamerası, muavin ikramı (çay, kek), mola yeri (dinlenme tesisi),
  hızlandırılabilir yolculuk (otoyol manzarası, gece/gündüz).
- Arabayla da gidilebilir: otoyol, gişe, benzinlik, dinlenme tesisi.

## 3. İkinci şehir (sahil/eğlence şehri)
- Küçük ama yoğun: sahil şeridi, otel bölgesi, eğlence caddesi.
- Gazino/kumarhane: rulet, blackjack, slot makinesi, tavla masası; jeton sistemi,
  kaybetme sınırı uyarısı, kazanç/kayıp istatistiği.
- Otel (mevcut otel sistemiyle), sahilde yürüyüş, iskele, balık restoranı.
- Dönüş otobüsü / araba ile dönüş.

## Sıra
1. Şehir üretici + Keçiören'in yerleştirilmesi (veri formatı birebir)
2. Sabit noktaların yeni haritaya taşınması, tüm testler
3. Otogar + bilet uygulaması + şehirlerarası otobüs
4. İkinci şehir + gazino
