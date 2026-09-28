// Job: saat kapanışı (her saat başı +90 sn).
// Biten saatin cüzdan → swap sayısı sayaçlarını okuyup bot/insan işlem sayılarını
// VolumeByHour satırına yazar ve sayacı siler.

import { CHAIN_IDS, chainToPrisma } from '@/lib/chains';
import { floorToHour, HOUR_MS } from '@/lib/analytics/stats';
import { splitBotHuman } from '@/lib/analytics/whales';
import { CACHE_KEYS } from '../cache';
import type { JobContext } from './context';

export async function finalizeHour(ctx: JobContext): Promise<void> {
  const previousHour = new Date(floorToHour(ctx.now()).getTime() - HOUR_MS);
  for (const chain of CHAIN_IDS) {
    const key = CACHE_KEYS.walletCounter(chain, previousHour);
    const counts = await ctx.cache.getFields(key);
    if (Object.keys(counts).length === 0) continue;

    const split = splitBotHuman(counts, ctx.config.BOT_TX_PER_HOUR);
    await ctx.prisma.volumeByHour.updateMany({
      where: { chain: chainToPrisma(chain), hourStart: previousHour },
      data: { botTxCount: split.botTxCount, humanTxCount: split.humanTxCount },
    });
    await ctx.cache.del(key);
    ctx.log.info(`finalizeHour: ${chain}`, { hour: previousHour.toISOString(), ...split });
  }
}
