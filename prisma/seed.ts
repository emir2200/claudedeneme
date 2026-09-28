// Demo verisiyle veritabanını doldurur: `npm run db:seed`
// Simülatörün ürettiği 5 haftalık geçmişi tablolara yazar; böylece API anahtarları olmadan
// canlı mod okuma yolu (PostgreSQL → Redis → dashboard) uçtan uca denenebilir.
// Uyarı: tüm tabloları temizler. Yalnızca geliştirme veritabanında çalıştırın.

import 'dotenv/config';
import { getPrisma } from '../src/server/db';
import { writeRawData } from '../src/server/seed';
import { simulatedSmartWallets, simulateRawData } from '../src/server/simulation';

async function main() {
  const prisma = getPrisma();
  const now = new Date();
  const raw = simulateRawData(now);
  await writeRawData(prisma, raw, simulatedSmartWallets(now));
  console.log(
    `Seed tamam: ${raw.tokens.length} token, ${raw.hours.length} saatlik kova, ${raw.chainStats.length} zincir görüntüsü, ` +
      `${raw.social.length} sosyal satır, ${raw.whales.length} balina swap'ı.`,
  );
  await prisma.$disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
