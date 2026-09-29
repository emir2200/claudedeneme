# Üç Başlı Ejderha — Roblox modeli

Altın pullu, üç uzun boyunlu, kanatlı ve iki kuyruklu bir ejderha. Her başın kendi boynuzları
(ortadakinde ve ejderhanın kendi sağındakinde hilal boynuzlar, solundakinde dikenli bir taç), kırmızı gözleri ve
boynunda kahverengi bir yelesi vardır; göğsünün iki yanında üç kırmızı çizgi bulunur.

Model hazır animasyonludur: üç baş birbirinden bağımsız hareket eder, kanatlar çırpılır, iki kuyruk
sallanır. Belirli aralıklarla üç baş birden geri kalkıp kükrer ve ağızlarından altın şimşekler çıkar.

**Dosya:** [`UcBasliEjderha.rbxmx`](UcBasliEjderha.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `UcBasliEjderha.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   ejderha dinlenme pozunda durur.

Hiçbir şey yüklemeniz (asset upload) gerekmez: ejderha Roblox'un temel parçalarından yapılmıştır,
şimşekler neon parçalarla çizilir, kıvılcımlar Roblox'un yerleşik dokusunu kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Üç ayrı baş | Her baş kendi hızında etrafına bakınır, başını kaldırıp indirir, çenesini oynatır. |
| Atışma | Yaklaşık her 11 saniyede bir yandaki iki baş ortadakine dönüp çenelerini şaklatır. |
| Nefes | Gövde yavaşça şişip iner. |
| Kanatlar | Omuz, dirsek ve bilekten dalga gibi çırpar; zarlar kemiklerle birlikte gerilir. |
| İki kuyruk | Ters fazlı dalgalarla sallanır. |
| Kükreme | Üç baş birden geri kalkar, sonra öne uzanıp yana açılır, çeneler sonuna kadar açılır ve her ağızdan ileri doğru uzayan, titreyen altın bir şimşek çıkar. Ağızlar ışık saçar, kıvılcımlar fışkırır, kanatlar genişçe açılır. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `UcBasliEjderha` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla kükrer. |
| `KukremeAraligi` | number | `15` | Otomatik kükremeler arası saniye (4.2'den büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Kükremeyi elle başlatmak için (aşağıya bakın). |

### Kükremeyi bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local ejderha = workspace.UcBasliEjderha
ejderha:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince kükresin
ejderha:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Kükreme sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `ejderha:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, ayakların arasındaki görünmez `Kok` parçasıdır (zemin hizası). Model -Z yönüne bakar.
- Boyut: Studio'daki **Scale** aracıyla ya da `ejderha:ScaleTo(2)` ile. Varsayılan boy ortadaki başın
  boynuzlarıyla yaklaşık 40 stud, kanat açıklığı yaklaşık 86 stud, burundan kuyruk uçlarına yaklaşık
  42 stud. Oyun sırasında ölçekleyecekseniz modeli Workspace'e koymadan önce ölçekleyin;
  animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera ejderhadan çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. Oyuncuların içinden geçmemesi için `Carpisma`
  klasöründe dört görünmez kutu (gövde, bacaklar, iki kuyruk) vardır; hareket eden boyunlar ve kanatlar
  çarpışmaz.
- Ses ve hasar yoktur; şimşekler yalnızca görseldir. Hasar vermek isterseniz kükreme sırasında
  başların önündeki alanı kontrol eden bir sunucu script'i ekleyebilirsiniz.
- Model yaklaşık 610 parçadan ve 53 kemikten oluşur; üç model içinde en ağırı budur.

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `ucbasli/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Geometri (gövde, üç boyun ve baş, kanatlar, bacaklar, iki kuyruk), renkler, şimşek parçaları; `.rbxmx` dosyasını yazar. |
| `src/rig.luau` | İskelet ve animasyon mantığı (baş başına hareketler, atışma, kükreme zamanlaması, kanat zarı üçgenleri). Üretilen kemik/parça verisiyle birlikte `UcBasliRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i (kanat zarlarını ve şimşekleri her karede çizer). |
