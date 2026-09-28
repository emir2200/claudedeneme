import { z } from 'zod';
import { CHAIN_IDS, type ChainId } from '@/lib/chains';

const optional = z.string().trim().min(1).optional();

const schema = z.object({
  DATA_MODE: z.enum(['demo', 'live']).default('demo'),
  DATABASE_URL: optional,
  REDIS_URL: optional,

  DEXSCREENER_BASE_URL: z.string().default('https://api.dexscreener.com'),
  GECKOTERMINAL_BASE_URL: z.string().default('https://api.geckoterminal.com/api/v2'),
  DEFILLAMA_BASE_URL: z.string().default('https://api.llama.fi'),
  LUNARCRUSH_API_KEY: optional,
  HELIUS_WEBHOOK_SECRET: optional,
  BSC_RPC_URL: optional,
  ROBINHOOD_RPC_URL: optional,

  ROBINHOOD_CHAIN_ID: z.coerce.number().int().positive().optional(),
  ROBINHOOD_DEXSCREENER_ID: z.string().default('robinhood'),
  ROBINHOOD_GECKO_NETWORK: z.string().default('robinhood'),
  ROBINHOOD_DEFILLAMA_NAME: z.string().default('Robinhood'),

  MILESTONE_USD: z.coerce.number().positive().default(100_000),
  WHALE_MIN_USD: z.coerce.number().positive().default(10_000),
  BOT_TX_PER_HOUR: z.coerce.number().int().positive().default(30),
});

export type Config = z.infer<typeof schema>;

let cached: Config | null = null;

/** Ortam değişkenlerini doğrular. Boş string'ler "tanımsız" sayılır. */
export function getConfig(): Config {
  if (cached) return cached;
  const env = Object.fromEntries(
    Object.entries(process.env).filter(([, v]) => v !== undefined && v.trim() !== ''),
  );
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    throw new Error(`Geçersiz ortam değişkenleri:\n${z.prettifyError(parsed.error)}`);
  }
  cached = parsed.data;
  return cached;
}

export interface ProviderIds {
  dexscreener: string;
  geckoterminal: string;
  defillama: string;
  rpcUrl: string | undefined;
}

/**
 * Sağlayıcıların zincir kimlikleri. Solana/BSC değerleri sağlayıcı belgelerindeki
 * standart kimliklerdir; Robinhood Chain için değerler ortamdan gelir (henüz doğrulanmadı).
 */
export function providerIds(config: Config = getConfig()): Record<ChainId, ProviderIds> {
  const ids: Record<ChainId, ProviderIds> = {
    solana: { dexscreener: 'solana', geckoterminal: 'solana', defillama: 'Solana', rpcUrl: undefined },
    bsc: { dexscreener: 'bsc', geckoterminal: 'bsc', defillama: 'BSC', rpcUrl: config.BSC_RPC_URL },
    robinhood: {
      dexscreener: config.ROBINHOOD_DEXSCREENER_ID,
      geckoterminal: config.ROBINHOOD_GECKO_NETWORK,
      defillama: config.ROBINHOOD_DEFILLAMA_NAME,
      rpcUrl: config.ROBINHOOD_RPC_URL,
    },
  };
  for (const id of CHAIN_IDS) if (!ids[id]) throw new Error(`Sağlayıcı kimliği eksik: ${id}`);
  return ids;
}
