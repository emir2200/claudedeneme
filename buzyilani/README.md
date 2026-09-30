# Buz Yılanı — Roblox modeli

Lavanta-mavi pullu, beyaz lekeli, sırtı ve başı buz tüyleriyle kaplı dev bir yılan. Gövdesi yerde
bir buçuk tur kıvrılır, halkanın arkasından yükselen boynu kemer çizerek öne eğilir; başının
çevresinde beyaz tüylerden bir yaka, mor gözleri ve iki uzun zehir dişi vardır. Çevresinde karla
kaplı buz kristali kümeleri durur.

Model hazır animasyonludur: gövde yerde hafifçe kayar, kuyruk ucu kıvrılır, boyun salınır, baş
etrafına bakar ve çatal dilini çıkarır, burnundan nefesle birlikte buhar çıkar. Belirli aralıklarla
boynunu geriye kıvırıp öne saldırır ve ağzından buz nefesi püskürtür.

**Dosya:** [`BuzYilani.rbxmx`](BuzYilani.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `BuzYilani.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   yılan dinlenme pozunda durur (kar taneleri ve sis düzenleme modunda da görünür).

Hiçbir şey yüklemeniz (asset upload) gerekmez: yılan Roblox'un temel parçalarından yapılmıştır
(tüyler Ice, beyaz lekeler Snow, kristaller Glass malzemesi), sis ve kar efektleri Roblox'un
yerleşik dokularını kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Kayma | Yerdeki halka boyunca çok hafif bir kayma dalgası ilerler; gövde yerden kalkmadan yerde kayar. |
| Kuyruk ucu | Uca doğru büyüyen bir dalgayla kıvrılıp açılır. |
| Boyun ve baş | Boyun nefesle salınır, baş etrafını süzer. |
| Çatal dil | Birkaç saniyede bir iki kez hızla dışarı çıkıp titrer. |
| Buhar | Her nefes verişte burun deliklerinden soğuk buhar çıkar. |
| Kar ve sis | Yılanın çevresinde kar taneleri süzülür, yerde soğuk sis sürünür. |
| Saldırı | Boyun geriye kıvrılıp baş yukarı kalkar, sonra öne atılır; ağız açılır ve buz nefesi (soğuk sis bulutu ve parıldayan buz kristalleri) püskürür, ağız soğuk bir ışıkla parlar, kuyruk ucu titrer. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `BuzYilani` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla saldırıp buz püskürtür. |
| `KukremeAraligi` | number | `14` | Otomatik saldırılar arası saniye (4'ten büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Saldırıyı elle başlatmak için (aşağıya bakın). |

### Saldırıyı bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local yilan = workspace.BuzYilani
yilan:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince saldırsın
yilan:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Saldırı sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `yilan:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, halkanın ortasındaki görünmez `Kok` parçasıdır (zemin hizası). Yılanın başı -Z yönüne bakar.
- Boyut: Studio'daki **Scale** aracıyla ya da `yilan:ScaleTo(2)` ile. Varsayılan boy boynun kemerinde
  yaklaşık 25 stud; yerdeki halkanın çapı yaklaşık 31 stud; gövdenin uzunluğu kuyruk ucundan başa
  yaklaşık 106 stud. Oyun sırasında ölçekleyecekseniz modeli Workspace'e koymadan önce ölçekleyin;
  animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera yılandan çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. Oyuncuların içinden geçmemesi için `Carpisma`
  klasöründe halkayı kaplayan görünmez bir silindir ve boyun için bir kutu vardır (halkanın ortası da
  kapalıdır). Buz kristalleri yalnızca görseldir.
- Ses ve hasar yoktur; buz nefesi yalnızca görseldir. Hasar ya da dondurma etkisi isterseniz saldırı
  sırasında başın önündeki alanı kontrol eden bir sunucu script'i ekleyebilirsiniz.
- Model yaklaşık 450 parçadan ve 26 kemikten oluşur.

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `buzyilani/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Gövde eğrisi (yerdeki sarmal ve yükselen boyun), kemikler, pullar, lekeler, buz tüyleri, baş, kristaller, efektler; `.rbxmx` dosyasını yazar. Desen sabit bir tohumla üretilir, her derlemede aynı çıkar. |
| `src/rig.luau` | İskelet ve animasyon mantığı (kayma dalgası, boyun, dil, saldırı zamanlaması). Üretilen kemik/parça verisiyle birlikte `YilanRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i. |
