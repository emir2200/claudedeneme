import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Memecoin Haritası',
  description: 'Solana, BNB Chain ve Robinhood Chain için memecoin ısı haritası ve aktivite analitiği',
};

export const viewport: Viewport = {
  themeColor: '#080a0f',
  colorScheme: 'dark',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="tr">
      <body className="min-h-screen">{children}</body>
    </html>
  );
}
