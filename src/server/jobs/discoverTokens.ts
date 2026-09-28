// Job: yeni token keşfi (her 2 dakikada bir).
// GeckoTerminal'in "yeni havuzlar" akışından son sayfaları okur, daha önce görülmemiş
// token'ları takip evrenine ekler. Launchpad ve narrative etiketleri eklenirken atanır.

import { CHAIN_IDS, chainToPrisma, normalizeAddress } from '@/lib/chains';
import { detectLaunchpad } from '@/lib/analytics/launchpads';
import { classifyNarratives } from '@/lib/analytics/narratives';
import { providerIds } from '../config';
import { fetchNewPools, type DiscoveredPool } from '../providers/geckoterminal';
import { errorInfo, type JobContext } from './context';

const PAGES_PER_RUN = 3;

export async function discoverTokens(ctx: JobContext): Promise<void> {
  const ids = providerIds(ctx.config);
  const now = ctx.now();

  for (const chain of CHAIN_IDS) {
    const pools: DiscoveredPool[] = [];
    for (let page = 1; page <= PAGES_PER_RUN; page++) {
      try {
        pools.push(...(await fetchNewPools(ids[chain].geckoterminal, page)));
      } catch (err) {
        ctx.log.warn(`discoverTokens: ${chain} sayfa ${page} alınamadı`, errorInfo(err));
        break;
      }
    }

    const unique = new Map<string, DiscoveredPool>();
    for (const p of pools) unique.set(normalizeAddress(chain, p.tokenAddress), p);

    const { count } = await ctx.prisma.token.createMany({
      data: [...unique].map(([address, p]) => ({
        chain: chainToPrisma(chain),
        address,
        symbol: p.symbol.slice(0, 32),
        name: p.name.slice(0, 128),
        launchpad: detectLaunchpad(chain, address, p.dexId),
        narratives: classifyNarratives(p.name, p.symbol),
        pairAddress: p.poolAddress,
        dexId: p.dexId,
        poolCreatedAt: p.poolCreatedAt,
        firstSeenAt: now,
      })),
      skipDuplicates: true,
    });
    ctx.log.info(`discoverTokens: ${chain}`, { seen: unique.size, inserted: count });
  }
}
