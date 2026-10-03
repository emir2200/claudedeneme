# Zırhlı Gergedan — Roblox modeli

Koyu gri derili dev bir gergedan: sırtını ve böğürlerini kaplayan kırık, köşeli zırh kıymıkları,
koyu tabandan altın uca doğru parlayan iki boynuz, dudaklarının arasından sızan ateş, gövdesine
serpilmiş kor zerreleri, ensesinde sert bir yele, boynunda ve yüzünde deri kıvrımları.

Model hazır animasyonludur. Bacaklar ters kinematikle (IK) hareket eder: ayaklar yere basılı kalır,
gergedan öne atılırken dirsekler ve dizler kendiliğinden bükülür. Gergedan ağır ağır nefes alır ve
bakınır, kulaklarını seğirtir, kuyruğunu savurur, burnundan soluk verir, ara sıra boğa gibi ön ayağıyla
yeri eşeler. Sırtından sürekli kıvılcımlar ve kopan zırh kıymıkları savrulur. Belirli aralıklarla başını
indirip yeri iki kez eşeler, sonra öne atılıp boynuzunu yukarı savurur.

**Dosya:** [`ZirhliGergedan.rbxmx`](ZirhliGergedan.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `ZirhliGergedan.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   gergedan dinlenme pozunda durur (kıvılcımlar ve duman düzenleme modunda da görünür).

Hiçbir şey yüklemeniz (asset upload) gerekmez: gergedan Roblox'un temel parçalarından yapılmıştır
(parlayan kısımlar Neon), efektler Roblox'un yerleşik dokularını kullanır.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Nefes ve bakınma | Gövde nefesle iner kalkar, ağırlığını sağa sola verir; baş ağır ağır sağa sola döner. Ayaklar yerinden kaymaz. |
| Kulak, kuyruk, soluk | Kulakları seğirir, kuyruğu savrulur; birkaç saniyede bir burnundan soluk verir. |
| Yer eşeleme | Ara sıra sağ ön ayağını kaldırıp öne uzatır, sonra yere basıp geriye doğru sürter; ayağın altından toz kalkar. |
| Kıvılcım ve kıymıklar | Sırtından geriye savrulan kıvılcımlar ve ince duman yükselir; zırh kıymıkları kopup havaya savrulur ve kaybolur. |
| Ateş ışıltısı | Boynuz uçları, ağız, karnın altı ve kor zerreleri nefesle birlikte parlayıp titreşir. |
| Hücum | Gergedan başını indirip boynuzunu öne doğrultur, ön ayağıyla iki kez yeri eşeler ve burnundan soluk verir; sonra öne atılır, ayaklarının altından toz bulutu kalkar ve başını hızla yukarı savurup böğürür. Boynuz uçlarından kıvılcımlar fışkırır, bütün ateş ışıltısı en parlak hâline çıkar. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `ZirhliGergedan` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla hücum eder. |
| `KukremeAraligi` | number | `14` | Otomatik hücumlar arası saniye (4.2'den büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Hücumu elle başlatmak için (aşağıya bakın). |

### Hücumu bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local gergedan = workspace.ZirhliGergedan
gergedan:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince hücum etsin
gergedan:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Hücum sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür. Öne atılma, hücum
başladıktan yaklaşık 1.4 saniye sonra, boynuz savurma 1.7 saniye sonra olur.

## Taşıma ve boyut

- Taşımak/döndürmek için: `gergedan:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, gergedanın altındaki görünmez `Kok` parçasıdır (zemin hizası). Gergedan -Z yönüne bakar.
  Ayaklar Kok'un yüksekliğindeki düz zemine basar.
- Model yerinde durur; hücumda yaklaşık 2 stud öne atılıp geri çekilir. Gerçekten koşturmak isterseniz
  sunucuda Kok'u `PivotTo` ile ilerletebilirsiniz; animasyon onu takip eder.
- Boyut: Studio'daki **Scale** aracıyla ya da `gergedan:ScaleTo(2)` ile. Varsayılan boyda omuz yüksekliği
  yaklaşık 11, boynuz ucu yaklaşık 12 stud; burundan kuyruğa yaklaşık 21 stud. Oyun sırasında
  ölçekleyecekseniz modeli Workspace'e koymadan önce ölçekleyin; animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera gergedandan çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır. `Carpisma` klasöründe gövde, bacaklar ve baş için üç görünmez
  kutu vardır.
- Ses ve hasar yoktur; hücum yalnızca görseldir.
- Model yaklaşık 380 parçadan oluşur (zırh kıymıklarının her biri iki parçadır).

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `gergedan/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Gövde, baş, boynuzlar, zırh kıymıkları, kor zerreleri, bacaklar, kuyruk, savrulan kıymıklar ve efektler; `.rbxmx` dosyasını yazar. Desen sabit bir tohumla üretilir, her derlemede aynı çıkar. |
| `src/rig.luau` | İskelet ve animasyon mantığı (nefes, bakınma, yer eşeleme, hücum ve boynuz savurma zamanlaması, ışıltı, savrulan kıymıklar, bacak IK'sı). Üretilen veriyle birlikte `GergedanRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i. |
