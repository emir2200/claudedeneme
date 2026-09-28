# Algoritmalar

Tüm hesaplamalar `src/lib/analytics/` altındaki saf, test edilmiş fonksiyonlardadır. Worker bu
fonksiyonları veritabanına yazmak için, snapshot üreticisi ise panel için çağırır. Ağırlıklar ve
eşikler kodda sabit olarak tanımlıdır; değiştirmek için ilgili dosyadaki sabiti güncellemek yeterlidir.

Ortak ilke: **ham değer yerine persentil.** Zincirler ve token'lar arasında ölçek farkı çok
büyüktür (Solana'nın saatlik hacmi Robinhood Chain'in 20–30 katı olabilir). Bu yüzden karşılaştırmalar
çoğunlukla ampirik persentil sırasıyla yapılır. Persentil ölçekten bağımsızdır ve tek bir aşırı
değere (bir pump saati, bir wash-trade token'ı) karşı dayanıklıdır.

---

## 1. Zincir Activity Index (0–100)

`src/lib/analytics/activityIndex.ts`

```
Momentum_c  = Σ_k w_k · P( x_c,k(şimdi) | x_c,k(son 168 saat) )
Baskınlık_c = min(1, pay_c × N / 2)          pay_c = 1s hacim_c / Σ 1s hacim
Index_c     = round(100 × (0.65 × Momentum_c + 0.35 × Baskınlık_c))
```

| Metrik (k) | Ağırlık w_k | Neden |
| --- | --- | --- |
| 1s DEX hacmi | 0.30 | Anlık para akışı |
| 1s işlem sayısı | 0.25 | Katılım genişliği (hacim birkaç balinayla şişebilir) |
| 1s yeni havuz sayısı | 0.20 | Launchpad iştahı, yeni coin arzı |
| 24s DEX hacmi | 0.15 | Kısa süreli sıçramaları dengeleyen taban |
| TVL | 0.10 | Yavaş değişen likidite derinliği |

- **Momentum** "bu zincir *kendi normaline göre* ne kadar sıcak?" sorusunu yanıtlar. Robinhood
  Chain'in rekor saati, Solana'nın sıradan saatinden daha sıcak görünebilir. Isı haritasının amacı
  da tam olarak bu "kayma"yı göstermektir.
- **Baskınlık** "para şu an *mutlak olarak* nerede?" sorusunu yanıtlar. N = 3 zincirde eşit pay
  (1/3) 0,5'e, hacmin ≥ 2/3'ünü alan zincir 1'e eşlenir.
- Eksik metrik (ör. TVL kaynağı yanıt vermedi) atlanır ve ağırlıklar yeniden normalize edilir.
- Etiketler: `<20 Donuk · <40 Soğuk · <60 Ilık · <80 Sıcak · ≥80 Kızgın`.
- Panelde her metrik hücresi kendi persentiline göre renklenir. İnce çizgi grafik, index'in son
  24 saatini gösterir (her saat için aynı formül, o saatten önceki 168 saatle hesaplanır).

## 2. 100K+ çıkış sayacı

`src/lib/analytics/milestones.ts` · job: `src/server/jobs/refreshMarkets.ts`

```
nitelikli(örnek) =
      (mcap ?? fdv) ≥ 100.000 $  VE  likidite ≥ 10.000 $     ← mcap yolu
   VEYA likidite ≥ 100.000 $                                  ← likidite yolu

her 5 dakikada, her aktif token için:
  eğer token zaten sayıldıysa           → değişiklik yok (ömür boyu bir kez)
  eğer nitelikli(örnek) değilse         → seri = 0
  değilse seri += 1; seri başlangıcı ??= örnek zamanı
          eğer seri ≥ 2                 → milestone100kAt = seri başlangıcı

günlük sayaç (bugün ve dün, her çalışmada yeniden sayılır):
  LaunchDaily[zincir, gün] = COUNT(tokens WHERE milestone100kAt ∈ gün) GROUP BY launchpad
```

- **İki ardışık örnek şartı** tek mumluk fitilleri ve anlık fiyat manipülasyonlarını eler.
- **Mcap yolunda asgari likidite** arzı kilitli, fiyatı şişirilmiş sahte "100K" token'ları eler.
- **Çıkış zamanı** onaylanan serinin ilk örneğidir. Gece yarısına yakın başlayıp ertesi gün
  onaylanan bir çıkış doğru güne yazılır; bu yüzden dünün sayacı da yeniden hesaplanır.
- **Launchpad'den bağımsızdır**: Pump.fun, Four.meme ya da doğrudan DEX'te açılan havuzlar aynı
  kuralla ölçülür. Launchpad yalnızca kırılım için etiketlenir.
- Paneldeki **tempo**: `(bugünkü sayı / günün geçen kısmı) / son 7 tam günün ortalaması − 1`.
  Günün ilk %5'inde gösterilmez.

TypeScript karşılığı (`refreshMarkets.ts` içinden, sadeleştirilmiş):

```ts
for (const chain of ['solana', 'bsc', 'robinhood']) {
  const tokens = await prisma.token.findMany({ where: { chain, isActive: true }, take: 1500 });
  for (const batch of chunk(tokens, 30)) {
    const pairs = await fetchTokenPairs(dexscreenerId[chain], batch.map((t) => t.address));
    for (const t of batch) {
      const m = summarizeToken(pairs, t.address); // en likit havuz + tüm havuzların toplamı
      totals.volume1h += m.volume1hUsd;            // → VolumeByHour / ChainStats
      const ms = advanceMilestone(t.milestoneState, { at: now, ...m });
      await prisma.token.update({ where: { id: t.id }, data: { ...m, ...ms } });
    }
  }
  await prisma.volumeByHour.upsert(/* (chain, bu saat) ← totals */);
  await prisma.chainStats.upsert(/* (chain, bu saat) ← totals + TVL */);
}
await updateActivityIndex(hourStart);  // son 168 saatlik ChainStats'a göre
await updateLaunchDaily(now);          // bugün + dün
```

**Saatlik hacim nasıl hesaplanır?** İçinde bulunulan saatin `VolumeByHour` satırı her 5 dakikada
takip evreninin kayan 1 saatlik hacim toplamıyla üzerine yazılır. Saatin son yazımı (~:55) o saatin
hacmini ±5 dakikalık kaymayla temsil eder. Bu yöntem, 5 dakikalık dilimleri toplamaya göre
kaçırılan çalışmalara karşı daha dayanıklıdır.

## 3. En aktif trade zamanı (24 × 7 matris)

`src/lib/analytics/tradeWindows.ts`

```
hücre(gün, saat) ← son 4 haftanın kapanmış saatlik kovaları (UTC haftanın saati)

hacim_m     = medyan(hacim)
volatilite_m = medyan(hacim ağırlıklı |1s fiyat değişimi|)
insan_payı  = Σ insan tx / Σ (insan + bot tx)

skor  = 0.55 × P(hacim_m) + 0.25 × P(volatilite_m) + 0.20 × P(insan_payı)   (168 hücre içinde)
ısı   = (skor − min) / (max − min)                                           (0–1)
```

- **Medyan**: tek bir pump saati hücreyi boyamaz. Hücre, "tipik bir Salı 15:00"ı temsil eder.
- **Hacim** likiditeyi (düşük kayma), **volatilite** fırsatı, **insan payı** bot gürültüsü
  dışındaki gerçek talebi temsil eder.
- İçinde bulunulan saat henüz kapanmadığı için matrise girmez.
- **Şu an aktif mi?** Seviye, bu haftanın-saatinin ısısından gelir (`≥0.66 aktif`,
  `≥0.33 normal`, aksi halde sakin). Canlı saat hacmi hücre medyanının ≥1,5 katıysa bir kademe
  yükselir, ≤0,6 katıysa bir kademe düşer.
- **Son 4 saatin en sıcağı**: içinde bulunulan saat dahil son 4 kovanın en yüksek hacimlisi.
- **Haftanın en iyi penceresi**: ortalama ısısı en yüksek 3 saatlik kesintisiz pencere (Pazar
  gecesinden Pazartesiye sarar).
- Matris UTC'de üretilir. İstemci, 168 hücrelik diziyi tarayıcının UTC farkı kadar döndürerek yerel
  saate çevirir (`rotateCells`).

## 4. Günün Coin'i (sosyal hype × on-chain)

`src/lib/analytics/hype.ts`

```
aday ⇔ likidite ≥ 25.000 $ VE MCap ≥ 100.000 $

mention_hızı = (mention_24s + 1) / (mention_önceki_24s + 1)
devir        = min(Vol_24s / MCap, 5)
sosyal/lik.  = etkileşim_24s / (likidite / 1.000)

hype = 100 × (0.35 × P(etkileşim) + 0.25 × P(mention_hızı) + 0.20 × P(devir) + 0.20 × P(24s fiyat değişimi))
```

- Adaylık eşiği, sosyal gürültünün henüz çıkış yapmamış token'ları öne itmesini önler.
- Devir 5x'te kırpılır: wash-trade yapılan bir token sınırsız puan toplayamaz.
- **Risk bayrakları** (sıralamayı değiştirmez, gösterilir):
  - `hype-likidite`: $1K likidite başına etkileşim adayların üst %10'unda ve > 50. Konuşulma
    derinliği aşıyor, yani kayma ve çıkış riski yüksek.
  - `asiri-devir`: Vol/MCap > 5, olası wash-trade veya bot hacmi.
  - `ince-likidite`: Likidite/MCap < %5.
  - `yeni-token`: havuz 6 saatten genç.
- **Günün Coin'i** = `asiri-devir` bayrağı olmayan en yüksek hype skoru. Bayraklı token'lar
  "Hype liderleri" listesinde ⚠ ile görünmeye devam eder.

## 5. Günün en hızlı yükselen narrative'i

`src/lib/analytics/narratives.ts`

**Sınıflandırma:** token adı + sembolü üzerinde anahtar kelime eşleşmesi. En az 4 harfli kelimeler
alt dize olarak aranır ("MEOWGPT" → Cat + AI). Kısa kelimeler ("ai", "cz", "gm") yalnızca kelime
sınırında ya da sembolün başında/sonunda eşleşir ("AIDOG" → AI, "RAIN" ✗). Bir token birden çok
narrative'e girebilir.

Tanımlı narrative'ler: AI Memes, Cat-Coins, Dog-Coins, Frog & Pepe, Meta-Tickers, PolitiFi,
CZ & Binance Kültürü, Hisse & Robinhood Memeleri.

```
momentum = 100 × (0.35 × P(mention büyümesi 24s/önceki 24s)
                + 0.25 × P(yeni token büyümesi 24s/önceki 24s)
                + 0.25 × P(24s hacim payı)
                + 0.15 × P(hacim ağırlıklı 24s fiyat değişimi))
```

En az 3 token'ı olan narrative'ler sıralamaya girer; tek token'lık "trendler" elenir.

## 6. Balinalar, smart money ve bot/insan ayrımı

`src/lib/analytics/whales.ts` · `src/server/ingest/swaps.ts`

- Swaplar zincirden bağımsız tek bir biçime (`SwapEvent`) normalize edilir:
  - **Solana (Helius webhook):** imzalayan cüzdanın takip edilen mint'teki *net* token değişimi.
    Pozitifse alım, negatifse satım; USD değeri = |miktar| × token fiyatı. `events.swap` yerine
    `tokenTransfers` kullanılır, çünkü pump.fun/PumpSwap işlemlerinde `events.swap` çoğu zaman boştur.
  - **EVM (BSC, Robinhood Chain):** Uniswap-V2 `Swap` logu. token0 = sayısal olarak küçük adres.
    Baz token havuzdan çıkıyorsa alımdır. USD değeri quote tarafından hesaplanır:
    `quote miktarı × (fiyatUSD / fiyatNative)`.
- **Balina:** USD değeri ≥ `WHALE_MIN_USD` (varsayılan 10.000 $). Kimlik `zincir:tx:logIndex`
  olduğundan tekrarlanan webhook'lar çift kayıt oluşturmaz.
- **Smart money:** `smart_wallets` tablosundaki etiketli cüzdanlar (manuel liste veya
  Nansen/Arkham gibi dış etiket kaynakları).
- **Bot/insan (saatlik):** her swap'ın aktörü o saatin Redis sayacına eklenir. Saat kapanınca
  `≥ BOT_TX_PER_HOUR` (varsayılan 30) swap yapan cüzdanların tüm işlemleri bot, kalanlar insan
  sayılır. Sniper, MEV ve volume-bot'lar bu eşiği kolayca aşar; insanlar nadiren aşar. Bilinen bot
  listeleriyle zenginleştirilebilir.
- **Net akış (1s):** son bir saatteki balina alımları − satımları, zincir başına.

---

## Parametre özeti

| Parametre | Varsayılan | Yer |
| --- | --- | --- |
| 100K eşiği | `MILESTONE_USD=100000` | ortam |
| Onay örneği sayısı | 2 (× 5 dk) | `DEFAULT_MILESTONE_CONFIG` |
| Mcap yolu asgari likidite | 10.000 $ | `DEFAULT_MILESTONE_CONFIG` |
| Balina eşiği | `WHALE_MIN_USD=10000` | ortam |
| Bot eşiği | `BOT_TX_PER_HOUR=30` | ortam |
| Activity Index penceresi | 168 saat | `snapshot.ts`, `refreshMarkets.ts` |
| Trade matrisi penceresi | 4 hafta | `MATRIX_WEEKS` |
| Hype adaylık eşiği | likidite 25.000 $, MCap 100.000 $ | `DEFAULT_HYPE_FILTERS` |
