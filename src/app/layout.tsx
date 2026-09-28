import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Chain Aktivite Radarı',
  description: "Günün, haftanın ve ayın en aktif chain'leri ve her chain'in gün içindeki en aktif trade saatleri",
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
