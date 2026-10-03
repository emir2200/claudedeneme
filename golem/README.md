# Lav Golemi — Roblox modeli

Kömür karası bazalttan yapılmış dev bir golem: bütün gövdesini saran, dallanan parlak lav çatlakları,
yüzeyine yarı gömülü köşeli kaya parçaları, iri omuz kayaları, dev yumruklar, kalın bacaklar ve
omuzlarının arasına gömülü küçük başında parlayan sarı gözler.

Model hazır animasyonludur. Bacaklar ters kinematikle (IK) hareket eder: ayaklar yere basılı kalır,
golem çömelirken dizler kendiliğinden bükülür. Golem ağır ağır nefes alır ve salınır, lav çatlakları
göğsündeki "kalpten" kollarına ve bacaklarına doğru yayılan bir kalp atışıyla parlayıp söner, ara sıra
kaslarını gerip yumruklarını sıkar. Belirli aralıklarla iki yumruğunu başının üstüne kaldırıp yere vurur:
yerde lavdan bir şok dalgası halkası yayılır, toz, lav sıçraması ve kaya parçaları savrulur, yakındaki
oyuncuların kamerası sarsılır.

**Dosya:** [`LavGolemi.rbxmx`](LavGolemi.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `LavGolemi.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   golem dinlenme pozunda durur (kor, duman ve lav damlaları düzenleme modunda da görünür).

Hiçbir şey yüklemeniz (asset upload) gerekmez: golem Roblox'un temel parçalarından yapılmıştır
(kaya Basalt ve Slate, lav Neon), efektler Roblox'un yerleşik dokularını kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Lav kalp atışı | Lav çatlakları iki vuruşlu bir kalp atışıyla parlar; parlama göğüsten kollara ve bacaklara doğru dalga gibi yayılır. |
| Ağır nefes ve salınım | Gövde yavaşça şişip iner, golem ağırlığını sağa sola verir; ayaklar yerinden kaymaz. |
| Bakınma | Baş yavaşça sağa sola döner. |
| Kas germe | Ara sıra kollarını hafifçe kaldırıp yumruklarını sıkar, çatlakları daha parlak yanar. |
| Kor, duman, lav | Göğsünden kor kıvılcımları yükselir, omuzlarından ince duman çıkar, yumruklarından lav damlar. |
| Yere vurma | Golem başını kaldırıp iki yumruğunu başının üstüne kaldırır ve geriye yaslanır; sonra çömelip yumruklarını önündeki yere indirir. Vurduğu anda yerde genişleyip sönen bir lav halkası yayılır, toz bulutu, lav sıçraması ve kaya parçaları savrulur, çatlakları ve gözleri en parlak hâline çıkar; yakındaki oyuncuların kamerası kısa bir süre sarsılır. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `LavGolemi` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla yere vurur. |
| `KukremeAraligi` | number | `14` | Otomatik saldırılar arası saniye (3.8'den büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KameraSarsintisi` | bool | `true` | Yere vurunca yakındaki (yaklaşık 90 stud içindeki) oyuncuların kamerası sarsılsın mı. |
| `KukremeZamani` | number | — | Saldırıyı elle başlatmak için (aşağıya bakın). |

### Saldırıyı bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local golem = workspace.LavGolemi
golem:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince vursun
golem:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Saldırı sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür. Yumruklar saldırı
başladıktan yaklaşık 1.1 saniye sonra yere değer; hasar vermek isterseniz bu anda golemin yaklaşık
5 stud önündeki alanı kontrol edebilirsiniz.

## Taşıma ve boyut

- Taşımak/döndürmek için: `golem:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, golemin altındaki görünmez `Kok` parçasıdır (zemin hizası). Golem -Z yönüne bakar.
  Ayaklar Kok'un yüksekliğindeki düz zemine basar.
- Boyut: Studio'daki **Scale** aracıyla ya da `golem:ScaleTo(2)` ile. Varsayılan boyda başının tepesi
  yaklaşık 14 stud, yumruklarıyla genişliği yaklaşık 16 stud. Oyun sırasında ölçekleyecekseniz modeli
  Workspace'e koymadan önce ölçekleyin; animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera golemden çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. `Carpisma` klasöründe gövde ve bacaklar için iki görünmez
  kutu vardır; kollar çarpışmaz.
- Ses ve hasar yoktur; şok dalgası ve lav yalnızca görseldir.
- Model yaklaşık 385 parçadan oluşur (yaklaşık 260'ı lav çatlağı).

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `golem/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Kaya kütleleri, lav çatlağı ağları, kaya parçaları, baş ve gözler, bacaklar, efektler ve şok dalgası halkası; `.rbxmx` dosyasını yazar. Desen sabit bir tohumla üretilir, her derlemede aynı çıkar. |
| `src/rig.luau` | İskelet ve animasyon mantığı (nefes, kas germe, yere vurma zamanlaması, lav kalp atışı, bacak IK'sı). Üretilen veriyle birlikte `GolemRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i (parlamayı, vurma efektlerini, şok dalgasını ve kamera sarsıntısını yönetir). |
