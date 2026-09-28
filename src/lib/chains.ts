// Takip edilen ağların tek kaynağı. Hem sunucu hem istemci tarafında kullanılır,
// bu yüzden burada gizli bilgi veya sağlayıcıya özel kimlik tutulmaz
// (onlar için bkz. src/server/config.ts).

export const CHAIN_IDS = ['solana', 'bsc', 'robinhood'] as const;
export type ChainId = (typeof CHAIN_IDS)[number];

/** Prisma `Chain` enum değerleri. */
export type PrismaChain = 'SOLANA' | 'BSC' | 'ROBINHOOD';

export interface ChainMeta {
  id: ChainId;
  prisma: PrismaChain;
  name: string;
  shortName: string;
  /**
   * Kategorik kimlik rengi. Koyu panel yüzeyinde (#10131a) renk körlüğü (CVD ΔE ≥ 8),
   * normal görüş (ΔE ≥ 15) ve kontrast (≥ 3:1) kontrollerinden geçen doğrulanmış palet:
   * mor (Solana), sarı (BNB), aqua (Robinhood).
   */
  color: string;
  nativeSymbol: string;
  /** İşlem bağlantısı ön eki; bilinmiyorsa null. */
  explorerTxUrl: string | null;
}

export const CHAINS: Record<ChainId, ChainMeta> = {
  solana: {
    id: 'solana',
    prisma: 'SOLANA',
    name: 'Solana',
    shortName: 'SOL',
    color: '#9085e9',
    nativeSymbol: 'SOL',
    explorerTxUrl: 'https://solscan.io/tx/',
  },
  bsc: {
    id: 'bsc',
    prisma: 'BSC',
    name: 'BNB Chain',
    shortName: 'BNB',
    color: '#c98500',
    nativeSymbol: 'BNB',
    explorerTxUrl: 'https://bscscan.com/tx/',
  },
  robinhood: {
    id: 'robinhood',
    prisma: 'ROBINHOOD',
    name: 'Robinhood Chain',
    shortName: 'HOOD',
    color: '#199e70',
    nativeSymbol: 'ETH',
    explorerTxUrl: process.env.NEXT_PUBLIC_ROBINHOOD_EXPLORER_TX_URL || null,
  },
};

export const CHAIN_LIST: ChainMeta[] = CHAIN_IDS.map((id) => CHAINS[id]);

export function chainFromPrisma(value: PrismaChain): ChainId {
  const found = CHAIN_LIST.find((c) => c.prisma === value);
  if (!found) throw new Error(`Bilinmeyen zincir: ${value}`);
  return found.id;
}

export function chainToPrisma(id: ChainId): PrismaChain {
  return CHAINS[id].prisma;
}

/** Adres karşılaştırmaları için kanonik biçim: EVM küçük harf, Solana (base58) olduğu gibi. */
export function normalizeAddress(chain: ChainId, address: string): string {
  return chain === 'solana' ? address : address.toLowerCase();
}
