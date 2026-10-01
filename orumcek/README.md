# Orman Örümceği — Roblox modeli

Yaprak yeşili, dev bir orman örümceği: altıgen plakalarla desenli iri karın, önde iki parlayan yeşil
göz ve üstte küçük kırmızı gözler, koyu kıvrık zehir dişleri, iki palp ve dizleri gövdenin üstüne
kalkan, koyu bantlı, kıllı sekiz uzun bacak.

Model hazır animasyonludur. Bacaklar ters kinematikle (IK) hareket eder: ayaklar yere basılı kalır,
gövde nefesle inip kalkarken ve sallanırken dizler kendiliğinden bükülür. Bacaklar ara sıra kalkıp
yere geri basar, zehir dişleri tıkırdar, palpler kıpırdar, dişlerden zehir damlar, karnın çevresinde
yeşil sporlar süzülür. Belirli aralıklarla şahlanıp ön bacaklarını havaya kaldırır, dişlerini açar,
sonra öne atılıp yeşil zehir püskürtür.

**Dosya:** [`OrmanOrumcegi.rbxmx`](OrmanOrumcegi.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `OrmanOrumcegi.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   örümcek dinlenme pozunda durur.

Hiçbir şey yüklemeniz (asset upload) gerekmez: örümcek Roblox'un temel parçalarından yapılmıştır,
zehir ve spor efektleri Roblox'un yerleşik dokularını kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Nefes ve salınım | Gövde yavaşça inip kalkar, sağa sola salınır; karın nefesle oynar. Ayaklar yerinden kaymaz, dizler bükülür. |
| Bacak tıkırtısı | Her bacak birkaç saniyede bir sırayla kalkıp yere geri basar. |
| Zehir dişleri ve palpler | Dişler ara sıra tıkırdar, palpler sürekli kıpırdar; diş uçlarından zehir damlar. |
| Sporlar ve gözler | Karnın çevresinde yeşil sporlar süzülür, yeşil gözlerin ışığı nabız gibi atar. |
| Saldırı | Örümcek şahlanır, ön iki çift bacağını havaya kaldırır ve dişlerini iki yana açar; sonra ön bacaklarını yere vurup öne atılır, dişlerini kapatır ve ağzından yeşil zehir sisi ve damlacıkları püskürtür. Gözler parlar. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `OrmanOrumcegi` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla saldırıp zehir püskürtür. |
| `KukremeAraligi` | number | `13` | Otomatik saldırılar arası saniye (3.7'den büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Saldırıyı elle başlatmak için (aşağıya bakın). |

### Saldırıyı bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local orumcek = workspace.OrmanOrumcegi
orumcek:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince saldırsın
orumcek:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Saldırı sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `orumcek:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, örümceğin altındaki görünmez `Kok` parçasıdır (zemin hizası). Örümcek -Z yönüne bakar.
  Ayaklar Kok'un yüksekliğindeki düz zemine basar; eğimli zeminde bazı ayaklar havada ya da yerin
  içinde kalabilir.
- Boyut: Studio'daki **Scale** aracıyla ya da `orumcek:ScaleTo(2)` ile. Varsayılan boy dizlerde ve karının
  üstünde yaklaşık 14 stud; bacaklar açıkken genişliği yaklaşık 37, ön ayaklardan karnın ucuna boyu
  yaklaşık 30 stud. Oyun sırasında ölçekleyecekseniz modeli Workspace'e koymadan önce ölçekleyin;
  animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera örümcekten çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır; gövde ve karnın çevresinde görünmez bir kutu vardır.
  Bacaklar çarpışmaz, oyuncular bacakların arasından geçebilir.
- Ses ve hasar yoktur; zehir yalnızca görseldir. Hasar ya da zehirlenme etkisi isterseniz saldırı
  sırasında örümceğin önündeki alanı kontrol eden bir sunucu script'i ekleyebilirsiniz.
- Model yaklaşık 235 parçadan oluşur (77'si karın ve sırttaki desen çizgileri).

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `orumcek/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Gövde, desenli karın, gözler, dişler, palpler, sekiz bacak ve efektler; `.rbxmx` dosyasını yazar. Bacak parçaları, oyundaki ters kinematik işleviyle hesaplanan dinlenme çerçevelerine göre yerleştirilir. |
| `src/rig.luau` | Gövde kemikleri, bacakların ters kinematiği, ayak hedefleri (bacak kaldırma, saldırı) ve saldırı zamanlaması. Üretilen veriyle birlikte `OrumcekRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i. |
