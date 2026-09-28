// Job: sosyal nabız (her 15 dakikada bir).
// Hacme göre ilk 40 uygun token için LunarCrush'tan saatlik cashtag serisini çeker ve
// son 48 saati SocialMetrics'e yazar (upsert — geç gelen düzeltmeler üzerine yazılır).

import { HOUR_MS } from '@/lib/analytics/stats';
import { cashtag, fetchTopicHourly } from '../providers/lunarcrush';
import { errorInfo, type JobContext } from './context';

const TOKENS_PER_RUN = 40;

export async function socialPulse(ctx: JobContext): Promise<void> {
  const apiKey = ctx.config.LUNARCRUSH_API_KEY;
  if (!apiKey) {
    ctx.log.info('socialPulse: LUNARCRUSH_API_KEY yok, atlandı');
    return;
  }
  const since = new Date(ctx.now().getTime() - 48 * HOUR_MS);
  const tokens = await ctx.prisma.token.findMany({
    where: { isActive: true, liquidityUsd: { gte: 25_000 }, marketCapUsd: { gte: 100_000 } },
    orderBy: { volume24hUsd: { sort: 'desc', nulls: 'last' } },
    take: TOKENS_PER_RUN,
    select: { id: true, symbol: true },
  });

  for (const token of tokens) {
    try {
      const points = (await fetchTopicHourly(cashtag(token.symbol), apiKey)).filter((p) => p.hourStart >= since);
      await ctx.prisma.$transaction(
        points.map((p) => {
          const data = {
            mentions: p.mentions,
            engagements: p.engagements,
            uniqueAuthors: p.uniqueAuthors,
            sentiment: p.sentiment,
          };
          return ctx.prisma.socialMetrics.upsert({
            where: { tokenId_source_hourStart: { tokenId: token.id, source: 'AGGREGATED', hourStart: p.hourStart } },
            create: { tokenId: token.id, source: 'AGGREGATED', hourStart: p.hourStart, ...data },
            update: data,
          });
        }),
      );
    } catch (err) {
      ctx.log.warn(`socialPulse: ${token.symbol} alınamadı`, errorInfo(err));
    }
  }
}
