// Job: saklama politikası (her gün 03:00 UTC).
//   SocialMetrics 14 gün · WhaleTrade 30 gün · ChainStats / VolumeByHour 120 gün
//   Takipten çıkmış ve 100K'yı hiç geçmemiş token'lar 30 gün sonra silinir
//   (100K'yı geçenler geçmiş sayaçların kaynağı olduğu için tutulur).

import { DAY_MS } from '@/lib/analytics/stats';
import type { JobContext } from './context';

export async function prune(ctx: JobContext): Promise<void> {
  const now = ctx.now().getTime();
  const before = (days: number) => new Date(now - days * DAY_MS);
  const [social, whales, stats, hours, tokens] = await Promise.all([
    ctx.prisma.socialMetrics.deleteMany({ where: { hourStart: { lt: before(14) } } }),
    ctx.prisma.whaleTrade.deleteMany({ where: { blockTime: { lt: before(30) } } }),
    ctx.prisma.chainStats.deleteMany({ where: { hourStart: { lt: before(120) } } }),
    ctx.prisma.volumeByHour.deleteMany({ where: { hourStart: { lt: before(120) } } }),
    ctx.prisma.token.deleteMany({
      where: { isActive: false, milestone100kAt: null, updatedAt: { lt: before(30) } },
    }),
  ]);
  ctx.log.info('prune', {
    social: social.count,
    whales: whales.count,
    chainStats: stats.count,
    volumeByHour: hours.count,
    tokens: tokens.count,
  });
}
