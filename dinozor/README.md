# Lav Dinozoru — Roblox modeli

Kömür karası kabuğu lav çatlaklarıyla kaplı, sırtındaki dikenleri alev alev yanan bir T-rex.
Model hazır animasyonludur: nefes alır, etrafına bakınır, kuyruğunu sallar, ağzı aralık ve içi
lav gibi parlar, çenesinden ve karnından lav damlar. Belirli aralıklarla başını kaldırıp ağzını
sonuna kadar açarak alev ve lav püskürten bir kükreme yapar.

**Dosya:** [`LavDinozoru.rbxmx`](LavDinozoru.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `LavDinozoru.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   dinozor dinlenme pozunda durur (alevler ve duman düzenleme modunda da görünür).

Hiçbir şey yüklemeniz (asset upload) gerekmez: dinozor Roblox'un temel parçalarından yapılmıştır,
alev/duman/kıvılcım efektleri Roblox'un yerleşik dokularını kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Lav nabzı | Gövdedeki lav çatlakları nefesle birlikte parlayıp söner; parlama göğüsten başa, bacaklara ve kuyruk ucuna doğru dalga gibi yayılır. |
| Nefes ve bakınma | Gövde yavaşça şişip iner, boyun ve baş sağa sola döner. |
| Ağız | Hep biraz aralıktır; içi lav gibi parlar, ağzından küçük alevler taşar. |
| Damlayan lav | Çenenin, boynun, karnın ve kuyruğun altından sarkan lav damlaları uzar, kopar ve yere düşer. Damlalar dinozor başını çevirse de hep aşağı sarkar. |
| Yanan sırt | Uzun sırt dikenlerinin tepesinde sürekli alev, sırttan yükselen kara duman ve kıvılcımlar. |
| Kuyruk ve kollar | Kuyruk uca doğru gecikmeli bir dalgayla sallanır, kısa ön kollar seğirir. |
| Kükreme | Önce başını kaldırıp ağzını kapatır, sonra ileri uzanıp ağzını sonuna kadar açar ve başını sallayarak kükrer: ağzından alev, duman ve yere düşen lav damlaları püskürür, sırt alevleri büyür, çatlaklar en parlak hâline çıkıp titreşir. |

Ayakların dibinde ve damlaların düştüğü yerlerde yerde parlayan lav gölleri vardır.

## Ayarlar (modelin öznitelikleri)

Explorer'da `LavDinozoru` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla kükrer. |
| `KukremeAraligi` | number | `12` | Otomatik kükremeler arası saniye (4'ten büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Kükremeyi elle başlatmak için (aşağıya bakın). |

### Kükremeyi bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local dinozor = workspace.LavDinozoru
dinozor:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince kükresin
dinozor:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Kükreme sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `dinozor:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, ayakların arasındaki görünmez `Kok` parçasıdır (zemin hizası). Model -Z yönüne bakar.
- Boyut: Studio'daki **Scale** aracıyla ya da `dinozor:ScaleTo(2)` ile. Varsayılan boy kalçada
  yaklaşık 13 stud, başta 19 stud, sırt dikenlerinin ucunda 22 stud; burundan kuyruk ucuna yaklaşık
  58 stud. Oyun sırasında ölçekleyecekseniz modeli Workspace'e koymadan önce ölçekleyin;
  animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera dinozordan çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. Oyuncuların içinden geçmemesi için `Carpisma`
  klasöründe dört görünmez kutu (gövde, baş, bacaklar, kuyruk) vardır. Lav gölleri de yalnızca görseldir.
- Ses ve hasar yoktur; alev ve lav yalnızca görseldir. Hasar vermek isterseniz kükreme sırasında
  ağzın önüne bir alan (ör. `workspace:GetPartBoundsInBox`) kontrol eden bir sunucu script'i ekleyebilirsiniz.
- Model yaklaşık 550 parçadan (bunların 330'u lav çatlağı) ve 26 kemikten oluşur.

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `dinozor/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Geometri, lav çatlağı ağı, sırt dikenleri, damlalar, göller, efektler; `.rbxmx` dosyasını yazar. Çatlak deseni sabit bir tohumla üretilir, her derlemede aynı çıkar. |
| `src/rig.luau` | İskelet ve animasyon mantığı (pozlar, kükreme zamanlaması, lav nabzı, damla döngüsü). Üretilen kemik/parça verisiyle birlikte `DinozorRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i. |
