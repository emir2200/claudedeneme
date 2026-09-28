# Chain Aktivite Radarı

**Günün, haftanın ve ayın en aktif chain'leri ve her chain'in gün içindeki en aktif trade saatleri.**

Panel yalnızca gerçek veri gösterir. Veri kaynağına ulaşılamazsa uydurma rakam yerine
"veri alınamadı" mesajı ve sebebi görünür.

## Ne gösterir?

| Bölüm | İçerik |
| --- | --- |
| **Dönem liderleri** | Günün, haftanın ve ayın en aktif chain'i: DEX hacmi, toplam içindeki payı, önceki döneme göre değişimi, ardından gelen iki chain |
| **Chain sıralaması** | Tüm chain'lerin gün / hafta / ay sıralaması, pay çubuğu, değişim, son 30 günün eğrisi. Bir chain'e tıklayınca saatleri açılır |
| **Gün içi en aktif trade saatleri** | Seçili chain için en aktif ve en sakin 3 saat, "şu an aktif mi?", 24 saatlik tipik gün grafiği (bugünün saatleriyle karşılaştırmalı), haftanın saatleri ısı matrisi. Yerel saat / UTC seçilebilir; her grafiğin tablo görünümü var |

## Kurulum ve çalıştırma

Node.js 20.9 veya üstü ve internet bağlantısı yeterli. API anahtarı gerekmez.

```sh
npm install
npm run dev
```

Ardından http://localhost:3000 adresini açın. `npm run dev` açık kaldığı sürece site çalışır.

Üretim için: `npm run build && npm start`.

## Kullanılan API'ler

| API | Adres | Ne için | Anahtar | Sınır |
| --- | --- | --- | --- | --- |
| **DefiLlama** | `api.llama.fi` | Chain başına günlük DEX hacmi → gün / hafta / ay sıralaması | Gerekmez | Cömert |
| **GeckoTerminal** | `api.geckoterminal.com` | Chain'in en yüksek hacimli havuzları ve saatlik hacimleri → gün içi saatler | Gerekmez | Dakikada ~30 istek |

Sunucunun bu iki adrese internet erişimi olmalıdır. Kurumsal ağ, güvenlik duvarı veya
bulut ortamı bu adresleri engelliyorsa panel "Kaynak erişimi reddetti" hatası gösterir.

İsteğe bağlı iyileştirme (henüz eklenmedi): **Dune Analytics** (`api.dune.com`, anahtar gerekir)
ile saatlik hacim, yalnızca en büyük havuzlardan değil chain'deki tüm DEX işlemlerinden hesaplanabilir.

## Nasıl hesaplanır?

**Aktivite ölçüsü:** chain'deki tüm DEX'lerin toplam işlem hacmi (USD).

**Gün / hafta / ay** (`src/lib/analytics/rankings.ts`): DefiLlama'nın günlük serisinden,
yalnızca tamamlanmış UTC günleriyle kayan pencereler:

- gün = son tam gün, önceki güne göre değişim
- hafta = son 7 gün, önceki 7 güne göre değişim
- ay = son 30 gün, önceki 30 güne göre değişim

Yeterli günü olmayan yeni chain'lerde DefiLlama'nın kendi 7 ve 30 günlük toplamı kullanılır; bu
durumda değişim gösterilmez.

**Gün içi saatler** (`src/lib/analytics/hours.ts`): Chain'in en yüksek 24 saatlik hacimli 8
havuzunun son 28 günlük saatlik hacmi toplanır.

- **Tipik gün:** her saat için 28 günün **medyanı**. Tek bir olağandışı gün profili bozmaz.
- **En aktif ve en sakin saatler:** tipik günün en yüksek ve en düşük paylı 3 saatlik penceresi (gece yarısından sarar).
- **Şu an:** son tamamlanan saatin hacmi, o saatin tipik hacmiyle karşılaştırılır. Seviye (aktif / normal / sakin), saatin tipik yoğunluğuna göre belirlenir. Hacim tipiğin 1,5 katını aşarsa seviye bir kademe yükselir, 0,6 katının altında kalırsa bir kademe düşer.
- **Haftanın saatleri:** haftanın her saati için son 4 haftanın medyanı.

Tüm hesaplar UTC'dir; arayüz tarayıcının saat dilimine çevirir.

Sonuçlar sunucuda 30 dakika önbelleklenir. Kaynak geçici olarak yanıt vermezse son alınan
veri "kaynak yanıt vermiyor" uyarısıyla gösterilir.

## Chain listesi

Sıralamaya giren chain'ler ve sağlayıcılardaki kimlikleri `src/lib/chains.ts` dosyasındadır:
Ethereum, Solana, BNB Chain, Base, Arbitrum, Tron, Polygon, Avalanche, Optimism, Sui, Sonic, TON,
Aptos ve Robinhood Chain. Yeni bir chain eklemek için listeye bir satır eklemek yeterli.

Robinhood Chain'in kimlikleri tahmindir. Sağlayıcılar o chain'i listelemiyorsa sıralamanın
altında "Veri yok: Robinhood Chain (Kaynak bu chain'i listelemiyor)" yazar.

## Komutlar

| Komut | Açıklama |
| --- | --- |
| `npm run dev` | Geliştirme sunucusu |
| `npm run build` / `npm start` | Üretim derlemesi / sunucusu |
| `npm test` | Testler (Vitest) |
| `npm run typecheck` | TypeScript kontrolü |

## Proje yapısı

```
src/
  app/                       Sayfa ve API uçları: /api/rankings, /api/hours?chain=…
  components/dashboard/      Dönem liderleri, sıralama tablosu, saat analizi
  components/ui/             Ortak parçalar (Panel, Sparkline, Meter, …)
  lib/analytics/             Saf hesaplamalar: rankings.ts, hours.ts
  lib/chains.ts              Chain listesi ve sağlayıcı kimlikleri
  server/providers/          DefiLlama ve GeckoTerminal istemcileri
  server/reports.ts          Raporları üretir, önbellekler, hataları açıklar
tests/                       Birim ve uçtan uca (fetch taklitli) testler
```

## Bilinen sınırlamalar

- Gün içi saatler chain'in tamamını değil, en büyük 8 havuzunu temsil eder.
- GeckoTerminal'in istek sınırı yüzünden bir chain'in saatleri ilk açılışta 10–20 saniyede yüklenebilir; sonra önbellekten gelir.
- Adaptörler sağlayıcıların belgelenmiş yanıt biçimlerine göre yazıldı ve bu biçimi taklit eden verilerle test edildi. Geliştirme ortamında bu API'lere ağ erişimi olmadığından canlı yanıtla denenmedi. Her yanıt şema doğrulamasından geçer; biçim farklıysa panel hata gösterir.

---

Bu panel analitik amaçlıdır, yatırım tavsiyesi değildir.
