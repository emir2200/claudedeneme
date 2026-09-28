// Job: token keşfi (her 2 dakikada bir).
// GeckoTerminal'in "trend havuzlar" (zaten hacmi olan, günün aktif coin'leri) ve "yeni
// havuzlar" (az önce açılan, 100K adayı coin'ler) akışlarını okur, daha önce görülmemiş
// token'ları takip evrenine ekler. Launchpad ve narrative etiketleri eklenirken atanır.
// Sarılı native coin'ler ve stablecoin'ler (WSOL, USDC, WBNB, …) evrene alınmaz.

import { CHAIN_IDS, chainToPrisma, normalizeAddress } from '@/lib/chains';
import { detectLaunchpad, isNonMemeToken } from '@/lib/analytics/launchpads';
import { classifyNarratives } from '@/lib/analytics/narratives';
import { providerIds } from '../config';
import { fetchPools, type DiscoveredPool, type PoolFeed } from '../providers/geckoterminal';
import { errorInfo, type JobContext } from './context';

const PAGES_PER_FEED: Record<PoolFeed, number> = { trending_pools: 2, new_pools: 3 };
/** GeckoTerminal liste uçları sayfa başına 20 havuz döner; eksik sayfa son sayfadır. */
const GECKO_PAGE_SIZE = 20;

export async function discoverTokens(ctx: JobContext): Promise<void> {
  const ids = providerIds(ctx.config);
  const now = ctx.now();

  for (const chain of CHAIN_IDS) {
    const pools: DiscoveredPool[] = [];
    for (const [feed, pages] of Object.entries(PAGES_PER_FEED) as [PoolFeed, number][]) {
      for (let page = 1; page <= pages; page++) {
        try {
          const batch = await fetchPools(ids[chain].geckoterminal, feed, page);
          pools.push(...batch);
          if (batch.length < GECKO_PAGE_SIZE) break;
        } catch (err) {
          ctx.log.warn(`discoverTokens: ${chain} ${feed} sayfa ${page} alınamadı`, errorInfo(err));
          break;
        }
      }
    }

    const unique = new Map<string, DiscoveredPool>();
    for (const p of pools) {
      const address = normalizeAddress(chain, p.tokenAddress);
      if (!isNonMemeToken(chain, address, p.symbol)) unique.set(address, p);
    }

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
