# Sıradaki işler (paralel paket bitince)

## Serbest metro
- Sokaktaki metro girişinden menü/ışınlanma olmadan, merdivenden yürüyerek inilir (giriş sokakta fiziksel merdiven).
- Turnikede kart okutma (F), bakiye; istasyon seçimi menüsü yok: hangi yöndeki trene binersen oraya gider,
  peronda hat şeması ve yön tabelaları.
- Trenler tarifeye göre gelir: perondaki ekranda "Sonraki tren: 3 dk" geri sayımı; kaçırırsan sonrakini beklersin.
- Tren içinde serbest dolaşım: boş koltuğu seçip oturma (F), ayakta tutunarak bekleme; koltuklar yolcularla dolu olabilir.
- İstediğin durakta kapı açılınca kendin inersin; inmezsen tren devam eder. Anonslar ve durak ekranı.
- Genel ilke: oyun serbest olacak; ışınlanma/otomatik sahne yerine oyuncu her şeyi kendi yapar
  (otobüs, dolmuş, taksi, otel, dükkân için de aynı ilke).
- Hat her yerde yeraltında değil: bazı bölümlerde yer hizasında (açık hat), bazı bölümlerde viyadük/köprü üstünde gider;
  tren şehirde dışarıdan görünür (yoldan, tepeden bakınca geçen tren), içerideyken pencereden şehir/deniz manzarası.
  Yerüstü ve köprü istasyonları (merdiven/yürüyen merdivenle çıkılan yükseltilmiş peron) da olur.
  Özgün şehir tasarımında hat güzergâhı buna göre çizilir (yamaç -> viyadük, ova -> yer hizası, merkez -> tünel).

## Onaylanan yeni özellikler (özgün şehirle birlikte / sonrasında)
Deniz: plaj (yüzme, şezlong, köpekle koşu, voleybol); tekne sahibi olma/kiralama, açıkta balık; vapur/feribot (arabayla binilebilir).
Araç: ehliyet sınavı (sürücü kursu, direksiyon sınavı); araç bakımı — araba gittikçe içi ve dışı kirlenir
(dışta çamur/toz, içte FPS görünümünde kirli cam, toz, çöp), oto yıkamaya götürülür (dış yıkama + iç temizlik),
lastik, sanayide tamir, muayene, kaza hasarı; modifiye (boya, jant, cam filmi, egzoz, plaka); yamaç yolunda gece yarışı;
çekici ve otopark.
AVM: kıyafet mağazaları (deneyerek alma), bowling, yemek katı. (Sinema/oyun salonu şart değil.)
Spor salonu: çalıştıkça dayanıklılık + GÖRÜNÜR fizik değişimi (aşağıdaki karakter notuna bak).
Kuaför/berber: saç ve sakal.
Hastane: yaralanınca/bayılınca hastane odasında YATAKTA uyanma, yataktan kalkma, taburcu (fatura/sigorta) — hastane önünde doğma yok.
Okul/kurs: bitirince daha iyi işler.
Kendi işini kurma (dükkân kiralama, eleman, stok, fiyat).
Borsa ve döviz uygulaması.
İkinci el pazarı: telefonda ilan, satıcıyla konuşup pazarlık, araç satışında noter işlemi.
Sesli konuşma: oyuncu karakteri ve NPC'ler sesli konuşur (ElevenLabs, sınırlı sayıda kalıp cümle).
Gece hayatı: canlı müzik, meyhane/bar; içki içme, sarhoşluk (görüntü sallanır, sürüş zorlaşır), polis alkol çevirmesi,
yakalanınca ehliyete el konur (süre boyunca araç sürülemez).
Sigara içme (animasyon, duman, sağlık/dayanıklılık etkisi).
İSTENMEYENLER: daha çok hayvan türü, yavru. Çok oyunculu: en sona.

### Karakter notu (teknik)
- Model MakeHuman'dan üretiliyor (tools/make_human.py), şu an tek vücut tipi, tek saç modeli (kadın: at kuyruğu, erkek: kısa).
- Fizik değişimi: MakeHuman'ın kas/kilo hedeflerinden (minmuscle..maxmuscle, minweight..maxweight) ek blend shape'ler
  üretilip glb'ye eklenir; oyunda kas ve kilo değerine göre karıştırılır (spor -> kas artar, çok yemek -> kilo).
- Saç/sakal: MakeHuman CC0 saç modellerinden 6-8 saç + 3-4 sakal/bıyık parçası ayrı mesh olarak dışa aktarılır;
  berberde seçilen parça takılır, renk materyalden değişir.
- Kıyafet: MakeHuman CC0 giysi setlerinden ayrı üst/alt/ayakkabı parçaları; mağazada denenip alınır.

## Araç içi kamerada eller
- Şu an araç içi (FPS) kamerada karakter tamamen gizleniyor: direksiyon kendi kendine dönüyor, kol/el yok.
- Yapılacak: FPS'te baş gizli, kollar ve gövde görünür; eller direksiyona IK ile oturur ve simitle birlikte döner
  (motosikletteki gidon tutuşu gibi), vites/el freni için sağ el hareketi, aşağı bakınca bacaklar ve pedallar.
- Dış kamerada da eller simide tam otursun (şu an hazır "Driving" animasyonu, yaklaşık duruyor).
