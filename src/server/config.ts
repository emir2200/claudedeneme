// Sağlayıcı adresleri. Varsayılanlar gerçek API'lerdir; testlerde yerel bir sunucuya
// yönlendirmek için ortam değişkenleriyle değiştirilebilir.

export function baseUrls() {
  return {
    defillama: process.env.DEFILLAMA_BASE_URL?.trim() || 'https://api.llama.fi',
    geckoterminal: process.env.GECKOTERMINAL_BASE_URL?.trim() || 'https://api.geckoterminal.com/api/v2',
  };
}
