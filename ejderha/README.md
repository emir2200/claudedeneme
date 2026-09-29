# Ateş Ejderhası — Roblox modeli

Kızıl pullu, lav çatlaklı karınlı, kıvrık boynuzlu, kanatlı bir ateş ejderhası. Model hazır
animasyonludur: nefes alır, etrafına bakınır, kanat çırpar, kuyruğunu sallar ve belirli
aralıklarla şaha kalkıp ağzından alev püskürterek kükrer.

**Dosya:** [`AtesEjderhasi.rbxmx`](AtesEjderhasi.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `AtesEjderhasi.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   ejderha dinlenme pozunda durur.

Hiçbir şey yüklemeniz (asset upload) gerekmez: ejderha Roblox'un temel parçalarından yapılmıştır,
alev/duman/kıvılcım efektleri Roblox'un yerleşik dokularını kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Nefes | Gövde yavaşça şişip iner, karındaki lav çizgileri nefesle birlikte parlar. |
| Bakınma | Boyun ve baş sağa sola döner, hafifçe iner kalkar. |
| Kanatlar | Omuz, dirsek ve bilekten dalga gibi çırpar; zarlar kemiklerle birlikte gerilir. |
| Kuyruk | Uca doğru gecikmeli bir dalgayla sallanır. |
| Pençeler | Ön kollar ve pençeler hafifçe açılıp kapanır. |
| Kükreme | Baş geriye kalkar, sonra ileri uzanır; çene açılır, ağızdan alev ve duman çıkar, göğüs ve ağız ışıkları parlar, kanatlar genişçe açılır. |

Sürekli efektler: burun deliklerinden ince duman, göğüsteki lav çekirdeğinden uçuşan kıvılcımlar.

## Ayarlar (modelin öznitelikleri)

Explorer'da `AtesEjderhasi` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla kükrer. |
| `KukremeAraligi` | number | `14` | Otomatik kükremeler arası saniye (4'ten büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Kükremeyi elle başlatmak için (aşağıya bakın). |

### Kükremeyi bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local ejderha = workspace.AtesEjderhasi
ejderha:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince kükresin
ejderha:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Kükreme sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `ejderha:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, ayakların altındaki görünmez `Kok` parçasıdır (zemin hizası). Model -Z yönüne bakar.
- Boyut: Studio'daki **Scale** aracıyla ya da `ejderha:ScaleTo(2)` ile. Varsayılan boy başın tepesine
  kadar yaklaşık 34 stud (kanat uçlarıyla 38), kanat açıklığı yaklaşık 70 stud, burundan kuyruk
  ucuna yaklaşık 40 stud. Oyun sırasında ölçekleyecekseniz modeli
  Workspace'e koymadan önce ölçekleyin; animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera ejderhadan çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. Oyuncuların içinden geçmemesi için `Carpisma`
  klasöründe üç görünmez kutu (gövde, bacaklar, kuyruk) vardır.
- Ses ve hasar yoktur; alev yalnızca görseldir. Hasar vermek isterseniz kükreme sırasında
  ağzın önüne bir alan (ör. `workspace:GetPartBoundsInBox`) kontrol eden bir sunucu script'i ekleyebilirsiniz.
- Model yaklaşık 385 parça ve 40 kemikten oluşur.

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `ejderha/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Geometri, renkler, efektler; `.rbxmx` dosyasını yazar. |
| `src/rig.luau` | İskelet ve animasyon mantığı (pozlar, kükreme zamanlaması, kanat zarı üçgenleri). Üretilen kemik/parça verisiyle birlikte `EjderhaRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i. |
