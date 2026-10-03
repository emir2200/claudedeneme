# Dokuz Kuyruklu Tilki — Roblox modeli

Karbeyaz kürklü, dokuz kabarık kuyruğu yelpaze gibi açılan mistik bir tilki (kitsune): başının
arkasında altın bir hale, gözlerinin üstünde ve yanaklarında kırmızı çizgiler, alnında mavi bir
işaret, mavi gözler, sivri kulaklar, göğsünde kabarık bir yele ve siyah çoraplı bacaklar.

Model hazır animasyonludur. Dokuz kuyruğun her biri kendi fazında dalgalanır. Bacaklar ters
kinematikle (IK) hareket eder: patiler yere basılı kalır, gövde inip kalkarken dirsekler ve dizler
kendiliğinden bükülür. Tilki meraklı meraklı bakınır, göz kırpar, kulaklarını seğirtir ve ara sıra
bir ön patisini kaldırır; hale yavaşça döner, çevresinde ateş böcekleri süzülür. Belirli aralıklarla
başını gökyüzüne kaldırıp ulur: kuyrukları yelpaze gibi açılır, hale ve alnındaki işaret parlar,
her kuyruğun ucundan mavi bir tilki ateşi çıkıp tilkinin çevresinde döner.

**Dosya:** [`DokuzKuyrukluTilki.rbxmx`](DokuzKuyrukluTilki.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `DokuzKuyrukluTilki.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   tilki dinlenme pozunda durur (ateş böcekleri ve kuyruk pırıltıları düzenleme modunda da görünür).

Hiçbir şey yüklemeniz (asset upload) gerekmez: tilki Roblox'un temel parçalarından yapılmıştır
(kürk Fabric, hale ve işaretler Neon), ateş ve pırıltı efektleri Roblox'un yerleşik dokularını kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Dokuz kuyruk | Her kuyruk kendi fazında, uca doğru büyüyen dalgalarla salınır; kuyruk uçlarından hafif pırıltı dökülür. |
| Meraklı bakış | Baş bir süre bir yöne bakar, sonra yumuşakça başka yöne döner ve yana yatar. |
| Göz ve kulaklar | Göz kırpar (bazen iki kez üst üste), kulakları ara sıra seğirir. |
| Ön pati | Ara sıra bir ön patisini kaldırıp kıvırır, bir süre havada tutar. |
| Nefes | Gövde nefesle hafifçe iner kalkar; patiler yerinden kaymaz. |
| Hale ve ateş böcekleri | Başın arkasındaki altın hale yavaşça döner ve süzülür; çevrede ateş böcekleri uçuşur. |
| Uluma | Tilki önce hafifçe çömelir ve kuyruklarını sırtında toplar; sonra başını gökyüzüne kaldırıp ulur. Kuyrukları yelpaze gibi açılıp titrer, kulakları geriye yatar, hale hızla döner ve parlar, alnındaki işaret beyaza yakın parlar. Her kuyruğun ucundan bir mavi tilki ateşi çıkar ve dokuzu tilkinin çevresinde halka çizerek döner, uluma bitince kuyruklara geri döner. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `DokuzKuyrukluTilki` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla ulur ve tilki ateşlerini çağırır. |
| `KukremeAraligi` | number | `15` | Otomatik ulumalar arası saniye (4.4'ten büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Ulumayı elle başlatmak için (aşağıya bakın). |

### Ulumayı bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local tilki = workspace.DokuzKuyrukluTilki
tilki:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince ulusun
tilki:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Uluma sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `tilki:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, tilkinin altındaki görünmez `Kok` parçasıdır (zemin hizası). Tilki -Z yönüne bakar.
  Patiler Kok'un yüksekliğindeki düz zemine basar.
- Boyut: Studio'daki **Scale** aracıyla ya da `tilki:ScaleTo(2)` ile. Varsayılan boyda omuz yüksekliği
  yaklaşık 7, kulak uçları yaklaşık 12, en yüksek kuyruk ucu yaklaşık 17 stud; kuyruklar açıkken
  genişliği yaklaşık 19 stud. Oyun sırasında ölçekleyecekseniz modeli Workspace'e koymadan önce
  ölçekleyin; animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera tilkiden çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. `Carpisma` klasöründe gövde, bacaklar ve baş için üç görünmez
  kutu vardır; kuyruklar ve hale çarpışmaz.
- Ses ve hasar yoktur; tilki ateşleri yalnızca görseldir. Hasar ya da başka bir etki isterseniz uluma
  sırasında tilkinin çevresini kontrol eden bir sunucu script'i ekleyebilirsiniz.
- Model yaklaşık 370 parçadan ve 45 kemikten (36'sı kuyruklarda) oluşur.

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `tilki/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Gövde ve göğüs yelesi, baş, işaretler, kulaklar, hale, dokuz kuyruk, dört bacak, tilki ateşleri ve efektler; `.rbxmx` dosyasını yazar. Bacak parçaları, oyundaki ters kinematik işleviyle hesaplanan dinlenme çerçevelerine göre yerleştirilir. |
| `src/rig.luau` | İskelet ve animasyon mantığı (kuyruk dalgaları, bakış, göz kırpma, kulak seğirmesi, pati kaldırma, bacak IK'sı, uluma zamanlaması). Üretilen veriyle birlikte `TilkiRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i (bacakları, göz kapaklarını, parlamayı ve tilki ateşlerini her karede günceller). |
