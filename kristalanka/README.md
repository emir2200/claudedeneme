# Kristal Anka — Roblox modeli

Camdan bir anka kuşu: tüyleri şeffaf kristal yapraklar ve kıymıklar, başının yanında yıldız gibi
parlayan bir ışık, başının arkasında yelpaze gibi açılan uzun bir tepe, sarkan pençeler ve uçlarında
kristal damlalar olan beş uzun kuyruk kurdelesi. Kuş yerden yaklaşık 14 stud yükseklikte süzülür.

Model hazır animasyonludur: kanatlar bir süre güçlü çırpar, bir süre açık süzülür; gövde kanat
vuruşlarıyla inip kalkar, kurdeleler rüzgârda dalgalanan şeritler gibi kıvrılır, kanat uçlarından
ve kurdele damlalarından pırıltı dökülür. Belirli aralıklarla şahlanıp kanatlarını sonuna kadar açar
ve gagasını açıp çığlık atar: başındaki ışık parlar, her yöne kristal ışık patlaması saçılır.

**Dosya:** [`KristalAnka.rbxmx`](KristalAnka.rbxmx)

## Oyuna ekleme

1. Roblox Studio'da oyununuzu açın.
2. Explorer'da **Workspace**'e sağ tıklayın → **Insert from File...** → `KristalAnka.rbxmx` dosyasını seçin.
   (Dosyayı Studio penceresine sürükleyip bırakmak da olur.)
3. **Play** (F5) ile test edin. Animasyon yalnızca oyun çalışırken oynar; düzenleme modunda
   kuş dinlenme pozunda durur (baştaki ışık ve pırıltılar düzenleme modunda da görünür).

Hiçbir şey yüklemeniz (asset upload) gerekmez: kuş Roblox'un temel parçalarından yapılmıştır
(kristal kısımlar şeffaf Glass, parlak çizgiler Neon), pırıltılar Roblox'un yerleşik dokusunu kullanır.
Cam görünümü en iyi Roblox'un grafik kalitesi yüksekken görünür.

## Neler yapar?

| Hareket | Açıklama |
|---|---|
| Kanat çırpma ve süzülme | Kanatlar omuz, dirsek ve bilekten dalga gibi çırpar; yukarı vuruşta uçlar geriye katlanır. Yaklaşık 12 saniyelik döngüde güçlü çırpıştan sakin süzülmeye geçer. |
| Süzülen gövde | Aşağı vuruşta yükselir, yavaşça sağa sola yalpalar. |
| Baş ve tepe | Baş dengede durup etrafa bakar, tepe tüyleri kanat vuruşlarıyla sallanır. |
| Kurdeleler | Beş kuyruk kurdelesi uca doğru gecikmeli dalgalarla kıvrılır. |
| Pençeler | Bacaklar sarkar, pençeler ara sıra kapanıp açılır. |
| Pırıltı izi | Kanat uçlarından ve kurdele damlalarından sürekli pırıltı dökülür; baştaki ışık titreşir. |
| Çığlık | Kuş şahlanıp kanatlarını yukarı kaldırır, sonra sonuna kadar açar; gagasını açıp çığlık atar, gagasından kristal kırıntıları fışkırır, baştaki ışık büyüyüp parlar ve göğsünden her yöne bir ışık patlaması saçılır. |

## Ayarlar (modelin öznitelikleri)

Explorer'da `KristalAnka` modelini seçin → Properties → **Attributes**:

| Öznitelik | Tür | Varsayılan | Anlamı |
|---|---|---|---|
| `OtomatikKukreme` | bool | `true` | Kendiliğinden, belirli aralıklarla çığlık atar. |
| `KukremeAraligi` | number | `16` | Otomatik çığlıklar arası saniye (3.6'dan büyük olmalı). |
| `AnimasyonHizi` | number | `1` | Animasyon hızı çarpanı (0.5 = yavaş, 2 = hızlı). |
| `KukremeZamani` | number | — | Çığlığı elle başlatmak için (aşağıya bakın). |

### Çığlığı bir script'ten başlatmak

Sunucudaki bir `Script`ten (örneğin oyuncu yaklaşınca):

```lua
local anka = workspace.KristalAnka
anka:SetAttribute("OtomatikKukreme", false) -- yalnızca siz tetikleyince çığlık atsın
anka:SetAttribute("KukremeZamani", workspace:GetServerTimeNow())
```

Çığlık sunucu saatine göre zamanlandığı için bütün oyuncular aynı anda görür.

## Taşıma ve boyut

- Taşımak/döndürmek için: `anka:PivotTo(CFrame.new(0, 0, 50) * CFrame.Angles(0, math.rad(90), 0))`.
  Pivot, kuşun altındaki zemin hizasında duran görünmez `Kok` parçasıdır; kuş onun yaklaşık 14 stud
  üstünde süzülür. Daha yüksekte uçurmak için Kok'u yukarı taşıyın. Kuş -Z yönüne bakar.
- Kuşu bir yol boyunca uçurmak isterseniz sunucuda Kok'u her adımda `PivotTo` ile ilerletin;
  animasyon onu takip eder.
- Boyut: Studio'daki **Scale** aracıyla ya da `anka:ScaleTo(2)` ile. Varsayılan kanat açıklığı
  yaklaşık 50 stud, gagadan kurdele uçlarına yaklaşık 38 stud. Oyun sırasında ölçekleyecekseniz
  modeli Workspace'e koymadan önce ölçekleyin; animasyon ölçeği başlarken okur.

## Bilinmesi gerekenler

- Animasyon, modelin içindeki `Animasyon` script'inde (RunContext = **Client**) her oyuncunun
  bilgisayarında hesaplanır. Sunucuda parçalar dinlenme pozunda kalır; bu yüzden animasyon ağ trafiği
  oluşturmaz. Kamera kuştan çok uzaktayken güncelleme seyrekleşir.
- Görsel parçaların çarpışması kapalıdır; yalnızca gövdenin çevresinde görünmez bir kutu vardır.
  Hareket eden kanatlar ve kurdeleler çarpışmaz.
- Ses ve hasar yoktur; ışık patlaması yalnızca görseldir.
- Model yaklaşık 345 parçadan ve 38 kemikten oluşur.

## Kaynaktan yeniden üretme

Model, [Lune](https://github.com/lune-org/lune) 0.10 ile koddan üretilir. `kristalanka/` klasöründe:

```sh
lune run src/build.luau
```

| Dosya | İçerik |
|---|---|
| `src/build.luau` | Gövde, baş, tepe, kanat tüyleri, kurdeleler, bacaklar, efektler; `.rbxmx` dosyasını yazar. |
| `src/rig.luau` | İskelet ve animasyon mantığı (kanat vuruşu ve süzülme, kurdele dalgaları, çığlık zamanlaması). Üretilen kemik/parça verisiyle birlikte `AnkaRig` ModuleScript'ine dönüşür. |
| `src/animator.client.luau` | Modelin içindeki `Animasyon` script'i. |
