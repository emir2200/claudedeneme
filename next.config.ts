import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Sunucu tarafında kalan, bundle'lanmaması gereken bağımlılıklar.
  serverExternalPackages: ['pg', 'ioredis'],
};

export default nextConfig;
