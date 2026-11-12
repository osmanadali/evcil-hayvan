# Üretim promptları

Bu dosyadaki promptları olduğu gibi kopyalayıp yapıştırabilirsin. İngilizce yazdım, çünkü iki araç da İngilizce promptta daha iyi sonuç veriyor.

## A. Tripo ile 3B modeller

**Her model için aynı ayarlar**

- Model: en yeni sürüm (v3.0), Text to 3D
- Texture: açık, kalite **Detailed / HD**, PBR açık
- Face limit: araçlar için 60.000, bina ve durak için 60.000
- Rig / Animate: **kapalı** (hareketi oyunda ben veriyorum)
- Çıktı: **GLB** olarak indir ve bu sohbete yükle. Dosya adını aşağıdaki gibi verirsen karışmaz.

**Negative prompt (hepsinde aynı):**

```
cartoon, stylized, toy, low poly, text, letters, logo, brand name, license plate numbers, people, driver, passengers, ground plane, base, pedestal, open doors, damaged, rusty
```

Bir model beklediğin gibi çıkmazsa aynı promptla bir kez daha dene; ikinci deneme çoğu zaman farklı ve daha iyi oluyor. Çıkan modelin ekran görüntüsünü atarsan hangisini kullanacağımıza birlikte karar veririz.

### 1. Belediye otobüsü — `otobus.glb`

```
Photorealistic modern 12 metre city transit bus, realistic proportions, white body with a wide blue stripe along the sides, large tinted passenger windows, two double passenger doors on the right side closed, flat front with large windscreen and a blank black destination display above it, side mirrors, black rubber tyres with grey wheel hubs, wheels straight, clean factory condition, complete vehicle seen from all sides, game-ready vehicle asset
```

### 2. Metro treni vagonu — `metro.glb`

```
Photorealistic modern subway metro train car, single carriage, realistic proportions, brushed silver stainless steel body with a red stripe below the windows, three sliding double doors per side closed, large side windows, flat driver cab front with windscreen and headlights, grey roof with air conditioning units, steel wheel bogies underneath, complete train car seen from all sides, game-ready vehicle asset
```

### 3. Sarı taksi — `taksi.glb`

```
Photorealistic compact four door sedan taxi, realistic proportions, glossy yellow paint, small blank yellow roof light box, black tyres with silver alloy wheels, wheels straight, all doors and windows closed, dark tinted glass, clean condition, complete car seen from all sides, game-ready vehicle asset
```

### 4. Hatchback araba — `hatchback.glb`

```
Photorealistic small five door hatchback city car, realistic proportions, plain light grey paint, black tyres with silver wheels, wheels straight, all doors and windows closed, dark tinted glass, clean condition, complete car seen from all sides, game-ready vehicle asset
```

### 5. Dolmuş (minibüs) — `dolmus.glb`

```
Photorealistic passenger minibus van, realistic proportions, medium blue body with white roof, sliding side door closed, rows of side windows, black tyres with steel wheels, wheels straight, clean condition, complete vehicle seen from all sides, game-ready vehicle asset
```

### 6. Motosiklet — `motosiklet.glb`

```
Photorealistic 125cc commuter motorcycle standing perfectly upright with no rider and no kickstand, realistic proportions, red fuel tank, black seat, chrome exhaust, black engine, spoked wheels with black tyres, front wheel pointing straight ahead, handlebars straight, side mirrors, clean condition, complete motorcycle seen from all sides, game-ready vehicle asset
```

### 7. Scooter — `scooter.glb`

```
Photorealistic small city scooter moped standing perfectly upright with no rider and no kickstand, realistic proportions, white body panels, black seat, small black wheels, front wheel pointing straight ahead, handlebars straight, side mirrors, clean condition, complete scooter seen from all sides, game-ready vehicle asset
```

### 8. Bisiklet — `bisiklet.glb`

```
Photorealistic city bicycle standing perfectly upright with no rider and no kickstand, realistic proportions, dark green steel frame, black saddle, straight handlebars with black grips, thin spoked wheels with black tyres, front wheel pointing straight ahead, chain and pedals, rear rack, clean condition, complete bicycle seen from all sides, game-ready asset
```

Bisiklet ve motosiklette tekerlek telleri bazen dolu disk gibi çıkar; öyle olursa söyle, tekerleği oyunda ayrı yaparım.

### 9. Otobüs durağı — `durak.glb`

```
Photorealistic modern city bus stop shelter, realistic proportions, slim dark grey steel frame, clear glass back wall and one glass side wall, flat tinted glass roof, wooden slat bench inside, blank rectangular advertising panel on one side, small blank route sign on a pole, complete freestanding shelter seen from all sides, game-ready asset
```

### 10. Metro girişi — `metro_girisi.glb`

```
Photorealistic subway station street entrance, realistic proportions, concrete stairway descending below ground with stainless steel handrails, low grey granite walls around three sides of the stair opening, modern steel and glass canopy roof over the stairs, tall slim sign pole beside it with a blank red square sign, complete freestanding entrance seen from all sides, game-ready asset
```

### 11. Market binası — `market.glb`

```
Photorealistic small neighbourhood supermarket building, single storey, realistic modern Turkish street architecture, straight walls and right angles, light grey facade, wide glass shopfront with automatic sliding glass doors in the middle, shelves with groceries visible through the glass, long blank red signboard above the entrance, shopping trolleys lined up beside the door, flat roof, realistic materials, complete freestanding building seen from all sides
```

### 12. Fırın — `firin.glb`

```
Photorealistic small neighbourhood bakery shop building, single storey, realistic modern Turkish street architecture, straight walls and right angles, warm cream facade, glass shopfront with loaves of bread and pastries on display shelves, glass entrance door, plain brown fabric awning, blank wooden signboard with a simple wheat symbol, flat roof, realistic materials, complete freestanding building seen from all sides
```

### 13. Eczane — `eczane.glb`

```
Photorealistic small neighbourhood pharmacy shop building, single storey, realistic modern Turkish street architecture, straight walls and right angles, white facade, glass shopfront with shelves of medicine boxes visible, glass entrance door, blank white signboard above the door, small red letter-free cross style sign hanging on the corner, flat roof, realistic materials, complete freestanding building seen from all sides
```

**Öncelik sırası:** 1 (otobüs), 9 (durak), 10 (metro girişi), 6 (motosiklet), 8 (bisiklet). Diğerleri bunlardan sonra gelebilir. 13 modelin tamamı yaklaşık 390 Tripo kredisi tutar (model başına 30).

## B. GPT Image ile görseller

Görseller fotoğraf gibi değil, **oyun görseli** gibi durmalı: 3B oyun tanıtım resmi tarzı, temiz ve canlı. Her promptun başındaki
stil cümlesi bunu sağlıyor; fazla gerçekçi çıkarsa sonuna şunu ekle: `It must clearly look like 3D video game art, not a photograph.`

Oyun adını aşağıda **Patili Gezinti** yazdım. Adı değiştirdiysen (gönderdiğin görselde "Patili Dostum" yazıyordu) promptlardaki adı
ona göre değiştir ve bana da söyle, oyunun içinde de güncelleyeyim.

### 1. Yükleme ekranı (yatay, 16:9, en az 1920×1080)

```
High quality 3D video game key art in the style of a modern life-simulation mobile game: slightly stylized realistic characters with clean shapes and soft features, smooth simplified materials, vivid saturated colours, soft global illumination, clearly a rendered game scene and not a photograph. Wide landscape loading screen, 16:9. A young woman in a teal t-shirt and blue jeans walks a yellow Labrador retriever on a leash while an orange tabby cat trots beside them, on a sunny tree-lined residential street in Ankara, Turkey: five storey apartment blocks with balconies, raised paved sidewalks, parked cars, a small corner shop, a blue and white city bus in the distance. Warm late afternoon light, cheerful and playful mood. Keep the lower third uncluttered for a loading bar. In the upper left, the game title "Patili Gezinti" in large friendly rounded white lettering with a paw print. No other text, no logos, no watermarks.
```

### 2. Ana menü arka planı (yatay, 16:9)

```
High quality 3D video game key art in the style of a modern life-simulation mobile game: slightly stylized realistic animals with clean shapes, big expressive eyes kept natural, smooth simplified fur, vivid saturated colours, soft global illumination, clearly a rendered game scene and not a photograph. Wide landscape, 16:9. A green city park in Ankara, Turkey on a clear morning: a yellow Labrador retriever sitting on the grass looking at the camera with its tongue out, an orange tabby cat sitting next to it, a red ball on the grass in front of them, park trees and a fountain softly blurred behind, apartment buildings far away. The right half of the image is kept simple and softly blurred so menu buttons can be placed over it. No text, no logos, no watermarks.
```

### 3. Uygulama simgesi (kare, 1024×1024)

```
A mobile game app icon in polished 3D game art style, square 1:1, no text. A close-up friendly portrait of a slightly stylized yellow Labrador retriever and an orange tabby cat side by side, heads touching, smiling at the viewer, clean shapes, smooth simplified fur, glossy eyes, soft rim light, simple warm teal to green gradient background, strong clear silhouette that reads well at small size, safe margins on all sides. Clearly game art, not a photograph. No text, no letters, no border, no watermark.
```

### 4. Play Store öne çıkan görsel (yatay, 1024×500)

```
A wide promotional banner in polished 3D video game key art style, aspect ratio about 2:1, clearly a rendered game scene and not a photograph. On the right, a slightly stylized young woman throws a red ball in a sunny city park while a yellow Labrador retriever jumps to catch it and an orange tabby cat watches; apartment buildings and trees of Ankara, Turkey in the background, vivid colours, playful mood. On the left, over a soft blurred background, the game title "Patili Gezinti" in large friendly rounded white lettering with a paw print. No other text, no logos, no watermarks.
```

### 5. Arayüz stil örneği (yatay, 16:9) — bana tasarım yönü vermek için

```
A user interface design mockup for a 3D mobile pet life-simulation game on a tablet in landscape orientation, shown as a flat screen design, 16:9. Clean modern game HUD over a softly blurred sunny 3D game street scene: a small translucent dark rounded card in the top left with a dog avatar, name and four thin coloured status bars; a coin counter, a map button and a menu button as translucent dark round buttons in the top right; a small clock with a sun icon near the top centre; a translucent round virtual joystick in the bottom left; three round icon buttons with small white labels in the bottom right. White line icons, rounded friendly shapes, subtle glass blur, generous spacing, no clutter, playful but tidy game feel. Labels in Turkish: "Sev", "Mama", "Top At". No watermarks.
```

5 numaralı görselden birkaç farklı sürüm üretip beğendiğini gönderirsen arayüzü ona göre yeniden çizerim.

**Görselleri bana gönderirken:** PNG ya da JPG olarak bu sohbete yüklemen yeterli. Yükleme ekranı ve menü arka planını doğrudan oyuna koyarım, simgeyi uygulama simgesi yaparım.
