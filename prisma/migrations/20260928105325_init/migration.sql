-- CreateEnum
CREATE TYPE "Chain" AS ENUM ('SOLANA', 'BSC', 'ROBINHOOD');

-- CreateEnum
CREATE TYPE "Launchpad" AS ENUM ('PUMP_FUN', 'FOUR_MEME', 'OTHER');

-- CreateEnum
CREATE TYPE "SocialSource" AS ENUM ('X', 'TELEGRAM', 'FARCASTER', 'AGGREGATED');

-- CreateEnum
CREATE TYPE "TradeSide" AS ENUM ('BUY', 'SELL');

-- CreateTable
CREATE TABLE "tokens" (
    "id" TEXT NOT NULL,
    "chain" "Chain" NOT NULL,
    "address" TEXT NOT NULL,
    "symbol" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "launchpad" "Launchpad" NOT NULL DEFAULT 'OTHER',
    "narratives" TEXT[],
    "pairAddress" TEXT,
    "dexId" TEXT,
    "quoteAddress" TEXT,
    "poolCreatedAt" TIMESTAMP(3),
    "firstSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastRefreshedAt" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "priceUsd" DOUBLE PRECISION,
    "priceNative" DOUBLE PRECISION,
    "priceChange1hPct" DOUBLE PRECISION,
    "priceChange24hPct" DOUBLE PRECISION,
    "marketCapUsd" DOUBLE PRECISION,
    "fdvUsd" DOUBLE PRECISION,
    "liquidityUsd" DOUBLE PRECISION,
    "volume1hUsd" DOUBLE PRECISION,
    "volume24hUsd" DOUBLE PRECISION,
    "txCount1h" INTEGER,
    "txCount24h" INTEGER,
    "peakMarketCapUsd" DOUBLE PRECISION,
    "milestoneStreak" INTEGER NOT NULL DEFAULT 0,
    "milestonePendingAt" TIMESTAMP(3),
    "milestone100kAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "chain_stats" (
    "id" BIGSERIAL NOT NULL,
    "chain" "Chain" NOT NULL,
    "hourStart" TIMESTAMP(3) NOT NULL,
    "capturedAt" TIMESTAMP(3) NOT NULL,
    "volume1hUsd" DOUBLE PRECISION NOT NULL,
    "volume24hUsd" DOUBLE PRECISION NOT NULL,
    "txCount1h" INTEGER NOT NULL,
    "txCount24h" INTEGER NOT NULL,
    "newPools1h" INTEGER NOT NULL,
    "newPools24h" INTEGER NOT NULL,
    "tvlUsd" DOUBLE PRECISION,
    "dexVolume24hUsd" DOUBLE PRECISION,
    "activeTokens" INTEGER NOT NULL,
    "activityIndex" DOUBLE PRECISION,

    CONSTRAINT "chain_stats_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "volume_by_hour" (
    "chain" "Chain" NOT NULL,
    "hourStart" TIMESTAMP(3) NOT NULL,
    "volumeUsd" DOUBLE PRECISION NOT NULL,
    "txCount" INTEGER NOT NULL,
    "buyCount" INTEGER NOT NULL,
    "sellCount" INTEGER NOT NULL,
    "botTxCount" INTEGER NOT NULL DEFAULT 0,
    "humanTxCount" INTEGER NOT NULL DEFAULT 0,
    "volatilityPct" DOUBLE PRECISION NOT NULL,
    "newPools" INTEGER NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "volume_by_hour_pkey" PRIMARY KEY ("chain","hourStart")
);

-- CreateTable
CREATE TABLE "social_metrics" (
    "id" BIGSERIAL NOT NULL,
    "tokenId" TEXT NOT NULL,
    "source" "SocialSource" NOT NULL,
    "hourStart" TIMESTAMP(3) NOT NULL,
    "mentions" INTEGER NOT NULL,
    "engagements" INTEGER NOT NULL,
    "uniqueAuthors" INTEGER NOT NULL,
    "sentiment" DOUBLE PRECISION,

    CONSTRAINT "social_metrics_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "launch_daily" (
    "chain" "Chain" NOT NULL,
    "day" DATE NOT NULL,
    "crossed100k" INTEGER NOT NULL,
    "newTokens" INTEGER NOT NULL,
    "byLaunchpad" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "launch_daily_pkey" PRIMARY KEY ("chain","day")
);

-- CreateTable
CREATE TABLE "whale_trades" (
    "id" TEXT NOT NULL,
    "chain" "Chain" NOT NULL,
    "tokenId" TEXT,
    "tokenAddress" TEXT NOT NULL,
    "tokenSymbol" TEXT,
    "wallet" TEXT NOT NULL,
    "walletLabel" TEXT,
    "isSmartMoney" BOOLEAN NOT NULL DEFAULT false,
    "side" "TradeSide" NOT NULL,
    "usdValue" DOUBLE PRECISION NOT NULL,
    "txHash" TEXT NOT NULL,
    "blockTime" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "whale_trades_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "smart_wallets" (
    "chain" "Chain" NOT NULL,
    "address" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "source" TEXT,
    "addedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "smart_wallets_pkey" PRIMARY KEY ("chain","address")
);

-- CreateTable
CREATE TABLE "sync_cursors" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "sync_cursors_pkey" PRIMARY KEY ("key")
);

-- CreateIndex
CREATE INDEX "tokens_chain_milestone100kAt_idx" ON "tokens"("chain", "milestone100kAt");

-- CreateIndex
CREATE INDEX "tokens_chain_isActive_volume24hUsd_idx" ON "tokens"("chain", "isActive", "volume24hUsd");

-- CreateIndex
CREATE INDEX "tokens_chain_poolCreatedAt_idx" ON "tokens"("chain", "poolCreatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "tokens_chain_address_key" ON "tokens"("chain", "address");

-- CreateIndex
CREATE INDEX "chain_stats_hourStart_idx" ON "chain_stats"("hourStart");

-- CreateIndex
CREATE UNIQUE INDEX "chain_stats_chain_hourStart_key" ON "chain_stats"("chain", "hourStart");

-- CreateIndex
CREATE INDEX "volume_by_hour_hourStart_idx" ON "volume_by_hour"("hourStart");

-- CreateIndex
CREATE INDEX "social_metrics_hourStart_idx" ON "social_metrics"("hourStart");

-- CreateIndex
CREATE UNIQUE INDEX "social_metrics_tokenId_source_hourStart_key" ON "social_metrics"("tokenId", "source", "hourStart");

-- CreateIndex
CREATE INDEX "whale_trades_blockTime_idx" ON "whale_trades"("blockTime");

-- CreateIndex
CREATE INDEX "whale_trades_chain_blockTime_idx" ON "whale_trades"("chain", "blockTime");

-- AddForeignKey
ALTER TABLE "social_metrics" ADD CONSTRAINT "social_metrics_tokenId_fkey" FOREIGN KEY ("tokenId") REFERENCES "tokens"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whale_trades" ADD CONSTRAINT "whale_trades_tokenId_fkey" FOREIGN KEY ("tokenId") REFERENCES "tokens"("id") ON DELETE SET NULL ON UPDATE CASCADE;
