// Ham veriyi (RawDashboardData) veritabanına yazar. Seed betiği ve entegrasyon testleri kullanır.
// Uyarı: tüm tabloları temizler.

import type { PrismaClient } from '@/generated/prisma/client';
import { chainToPrisma, type ChainId } from '@/lib/chains';
import type { RawDashboardData } from '@/lib/types';

export async function writeRawData(
  prisma: PrismaClient,
  raw: RawDashboardData,
  smartWallets: ReadonlyArray<{ chain: ChainId; address: string; label: string }> = [],
): Promise<void> {
  const now = raw.now;
  await prisma.$transaction([
    prisma.whaleTrade.deleteMany(),
    prisma.socialMetrics.deleteMany(),
    prisma.token.deleteMany(),
    prisma.volumeByHour.deleteMany(),
    prisma.chainStats.deleteMany(),
    prisma.launchDaily.deleteMany(),
    prisma.smartWallet.deleteMany(),
    prisma.syncCursor.deleteMany(),
  ]);

  await prisma.token.createMany({
    data: raw.tokens.map((t) => ({
      chain: chainToPrisma(t.chain),
      address: t.address,
      symbol: t.symbol,
      name: t.name,
      launchpad: t.launchpad,
      narratives: t.narratives,
      poolCreatedAt: t.poolCreatedAt,
      firstSeenAt: t.poolCreatedAt ?? now,
      lastRefreshedAt: now,
      priceUsd: t.priceUsd,
      priceChange1hPct: t.priceChange1hPct,
      priceChange24hPct: t.priceChange24hPct,
      marketCapUsd: t.marketCapUsd,
      liquidityUsd: t.liquidityUsd,
      volume24hUsd: t.volume24hUsd,
      txCount24h: t.txCount24h,
      milestone100kAt: t.milestone100kAt,
      milestoneStreak: t.milestone100kAt ? 2 : 0,
    })),
  });
  const tokens = await prisma.token.findMany({ select: { id: true, chain: true, address: true } });
  const tokenId = new Map(tokens.map((t) => [`${t.chain}:${t.address}`, t.id]));

  await prisma.volumeByHour.createMany({
    data: raw.hours.map((h) => ({
      chain: chainToPrisma(h.chain),
      hourStart: h.hourStart,
      volumeUsd: h.volumeUsd,
      txCount: h.txCount,
      buyCount: h.buyCount,
      sellCount: h.sellCount,
      botTxCount: h.botTxCount,
      humanTxCount: h.humanTxCount,
      volatilityPct: h.volatilityPct,
      newPools: h.newPools,
    })),
  });

  await prisma.chainStats.createMany({
    data: raw.chainStats.map((s) => ({
      chain: chainToPrisma(s.chain),
      hourStart: s.hourStart,
      capturedAt: s.hourStart,
      volume1hUsd: s.volume1hUsd,
      volume24hUsd: s.volume24hUsd,
      txCount1h: s.txCount1h,
      txCount24h: s.txCount24h,
      newPools1h: s.newPools1h,
      newPools24h: s.newPools24h,
      tvlUsd: s.tvlUsd,
      activeTokens: 0,
    })),
  });

  await prisma.launchDaily.createMany({
    data: raw.launches.map((l) => ({
      chain: chainToPrisma(l.chain),
      day: new Date(`${l.day}T00:00:00Z`),
      crossed100k: l.crossed100k,
      newTokens: l.newTokens,
      byLaunchpad: l.byLaunchpad,
    })),
  });

  await prisma.socialMetrics.createMany({
    data: raw.social.flatMap((s) => {
      const id = tokenId.get(`${chainToPrisma(s.chain)}:${s.address}`);
      return id
        ? [
            {
              tokenId: id,
              source: 'AGGREGATED' as const,
              hourStart: s.hourStart,
              mentions: s.mentions,
              engagements: s.engagements,
              uniqueAuthors: s.uniqueAuthors,
              sentiment: s.sentiment,
            },
          ]
        : [];
    }),
  });

  await prisma.smartWallet.createMany({
    data: smartWallets.map((w) => ({ ...w, chain: chainToPrisma(w.chain), source: 'demo' })),
  });

  await prisma.whaleTrade.createMany({
    data: raw.whales.map((w) => ({
      id: w.id,
      chain: chainToPrisma(w.chain),
      tokenId: tokenId.get(`${chainToPrisma(w.chain)}:${w.tokenAddress}`) ?? null,
      tokenAddress: w.tokenAddress,
      tokenSymbol: w.tokenSymbol,
      wallet: w.wallet,
      walletLabel: w.walletLabel,
      isSmartMoney: w.isSmartMoney,
      side: w.side,
      usdValue: w.usdValue,
      txHash: w.txHash,
      blockTime: w.blockTime,
    })),
  });
}
