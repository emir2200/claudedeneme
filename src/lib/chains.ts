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
  explorerName: string;
  /** Token sayfası bağlantısı ön eki; bilinmiyorsa null. */
  explorerTokenUrl: string | null;
  /** dexscreener.com/<slug>/<adres> için zincir kimliği; doğrulanmamışsa null. */
  dexscreenerSlug: string | null;
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
    explorerName: 'Solscan',
    explorerTokenUrl: 'https://solscan.io/token/',
    dexscreenerSlug: 'solana',
  },
  bsc: {
    id: 'bsc',
    prisma: 'BSC',
    name: 'BNB Chain',
    shortName: 'BNB',
    color: '#c98500',
    nativeSymbol: 'BNB',
    explorerTxUrl: 'https://bscscan.com/tx/',
    explorerName: 'BscScan',
    explorerTokenUrl: 'https://bscscan.com/token/',
    dexscreenerSlug: 'bsc',
  },
  robinhood: {
    id: 'robinhood',
    prisma: 'ROBINHOOD',
    name: 'Robinhood Chain',
    shortName: 'HOOD',
    color: '#199e70',
    nativeSymbol: 'ETH',
    explorerTxUrl: process.env.NEXT_PUBLIC_ROBINHOOD_EXPLORER_TX_URL || null,
    explorerName: 'Blok gezgini',
    explorerTokenUrl: process.env.NEXT_PUBLIC_ROBINHOOD_EXPLORER_TOKEN_URL || null,
    dexscreenerSlug: null,
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

/** Bir token'ı doğrulamak için dış bağlantılar (blok gezgini, DEXScreener). */
export function tokenLinks(chain: ChainId, address: string): Array<{ label: string; href: string }> {
  const meta = CHAINS[chain];
  const links: Array<{ label: string; href: string }> = [];
  if (meta.explorerTokenUrl) links.push({ label: meta.explorerName, href: `${meta.explorerTokenUrl}${address}` });
  if (meta.dexscreenerSlug) links.push({ label: 'DEXScreener', href: `https://dexscreener.com/${meta.dexscreenerSlug}/${address}` });
  return links;
}
