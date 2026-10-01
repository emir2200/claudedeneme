# Raptor — Roblox modeli

Mavimsi gri pullu bir raptor: gözden boynun ve sırtın üstünden kuyruk ucuna uzanan mavi bir şerit,
yanlarında koyu benekler, açık renkli boğaz ve karın, kehribar rengi gözler, S biçimli uzun boyun,
uzun kıvrık pençeli kollar ve ayağın ikinci parmağında yerden kalkık duran büyük orak pençe.

Model hazır animasyonludur. Bacaklar ters kinematikle (IK) hareket eder: ayaklar yere basılı kalır,
raptor çömelip öne atılırken dizler kendiliğinden bükülür. Baş kuş gibi bakınır, raptor göz kırpar,
çenesini tıkırdatır, ağırlığını bir ayağından diğerine aktarır ve ara sıra orak pençesini yere tık tık
vurur. Belirli aralıklarla çömelip öne atılır ve başını kaldırıp çığlık atar.

**Dosya:** [`Raptor.rbxmx`](Raptor.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `Raptor.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   raptor dinlenme pozunda durur.

Hiçbir şey yüklemeniz (asset upload) gerekmez: raptor Roblox'un temel parçalarından yapılmıştır,
toz efekti Roblox'un yerleşik dokusunu kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Kuş gibi bakış | Baş birkaç saniye bir noktaya sabitlenir, sonra hızla yeni bir yöne döner ve merakla yana yatar. |
| Göz kırpma | Birkaç saniyede bir, bazen iki kez üst üste göz kırpar. |
| Çene tıkırtısı | Ara sıra çenesini hızlı hızlı tıkırdatır. |
| Nefes ve denge | Gövde nefesle hafifçe iner kalkar, kuyruk dengede sallanır. |
| Ağırlık aktarma | Ara sıra bir ayağını yerden kaldırıp yerine basar; gövde diğer ayağa yaslanır, ayak yere basınca küçük toz kalkar. |
| Orak pençe | Ara sıra bir ayağının orak pençesini yere tık tık vurur. |
| Kollar | Uzun parmaklı pençeler yavaşça kıvrılıp açılır. |
| Saldırı | Raptor çömelir, başını öne indirir, kollarını geri çeker ve kuyruğunu kaldırır; sonra öne atılır, ayaklarının altından toz kalkar, kollarını öne ve yana açar, başını kaldırıp ağzını sonuna kadar açarak çığlık atar ve kuyruğunu kamçılar. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `Raptor` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla öne atılıp çığlık atar. |
| `KukremeAraligi` | number | `12` | Otomatik saldırılar arası saniye (3.8'den büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Saldırıyı elle başlatmak için (aşağıya bakın). |

### Saldırıyı bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local raptor = workspace.Raptor
raptor:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince saldırsın
raptor:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Saldırı sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `raptor:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, raptorun altındaki görünmez `Kok` parçasıdır (zemin hizası). Raptor -Z yönüne bakar.
  Ayaklar Kok'un yüksekliğindeki düz zemine basar.
- Boyut: Studio'daki **Scale** aracıyla ya da `raptor:ScaleTo(0.5)` ile. Varsayılan boyda başı yerden
  yaklaşık 13 stud yüksekte, burundan kuyruk ucuna yaklaşık 28 stud; yani bir oyuncu karakterinin
  iki katından büyüktür. Oyuncu boyunda bir raptor isterseniz `ScaleTo(0.45)` civarı uygun olur.
  Oyun sırasında ölçekleyecekseniz modeli Workspace'e koymadan önce ölçekleyin; animasyon ölçeği
  başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera raptordan çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. Oyuncuların içinden geçmemesi için `Carpisma`
  klasöründe gövde, bacaklar ve kuyruk için üç görünmez kutu vardır; boyun ve baş çarpışmaz.
- Ses ve hasar yoktur; saldırı yalnızca görseldir. Hasar vermek isterseniz saldırı sırasında
  raptorun önündeki alanı kontrol eden bir sunucu script'i ekleyebilirsiniz.
- Model yaklaşık 265 parçadan ve 20 kemikten oluşur.

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `raptor/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Gövde eğrisi, mavi şerit, benekler, baş, kollar, bacaklar ve orak pençe, toz efektleri; `.rbxmx` dosyasını yazar. Bacak parçaları, oyundaki ters kinematik işleviyle hesaplanan dinlenme çerçevelerine göre yerleştirilir. |
| `src/rig.luau` | İskelet ve animasyon mantığı (kuş gibi bakış, göz kırpma, ağırlık aktarma, orak pençe vuruşu, bacak IK'sı, saldırı zamanlaması). Üretilen veriyle birlikte `RaptorRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i. |
