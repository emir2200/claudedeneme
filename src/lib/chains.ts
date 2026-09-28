// Sıralamaya giren chain'ler ve sağlayıcılardaki kimlikleri.
// Yeni bir chain eklemek için bu listeye bir satır eklemek yeterlidir.
//
// - llama: DefiLlama `/overview/dexs/{llama}` kimliği (küçük harf chain adı)
// - gecko: GeckoTerminal ağ kimliği (`/networks/{gecko}/...`)
// Kimlikler sağlayıcı belgelerine göre yazıldı. Robinhood Chain kimlikleri tahmindir;
// sağlayıcı o chain'i henüz listelemiyorsa panel onu "veri yok" olarak gösterir.

export interface ChainDef {
  id: string;
  name: string;
  llama: string;
  gecko: string;
}

export const CHAINS: readonly ChainDef[] = [
  { id: 'ethereum', name: 'Ethereum', llama: 'ethereum', gecko: 'eth' },
  { id: 'solana', name: 'Solana', llama: 'solana', gecko: 'solana' },
  { id: 'bsc', name: 'BNB Chain', llama: 'bsc', gecko: 'bsc' },
  { id: 'base', name: 'Base', llama: 'base', gecko: 'base' },
  { id: 'arbitrum', name: 'Arbitrum', llama: 'arbitrum', gecko: 'arbitrum' },
  { id: 'tron', name: 'Tron', llama: 'tron', gecko: 'tron' },
  { id: 'polygon', name: 'Polygon', llama: 'polygon', gecko: 'polygon_pos' },
  { id: 'avalanche', name: 'Avalanche', llama: 'avalanche', gecko: 'avax' },
  { id: 'optimism', name: 'Optimism', llama: 'optimism', gecko: 'optimism' },
  { id: 'sui', name: 'Sui', llama: 'sui', gecko: 'sui-network' },
  { id: 'sonic', name: 'Sonic', llama: 'sonic', gecko: 'sonic' },
  { id: 'ton', name: 'TON', llama: 'ton', gecko: 'ton' },
  { id: 'aptos', name: 'Aptos', llama: 'aptos', gecko: 'aptos' },
  { id: 'robinhood', name: 'Robinhood Chain', llama: 'robinhood', gecko: 'robinhood' },
];

const BY_ID = new Map(CHAINS.map((c) => [c.id, c]));

export function findChain(id: string): ChainDef | undefined {
  return BY_ID.get(id);
}
