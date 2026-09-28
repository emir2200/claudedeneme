import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@/generated/prisma/client';
import { getConfig } from './config';

// Next.js geliştirme modunda modül yeniden yüklemeleri bağlantı havuzunu çoğaltmasın diye
// istemci globalThis üzerinde tutulur.
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export function getPrisma(): PrismaClient {
  if (!globalForPrisma.prisma) {
    const url = getConfig().DATABASE_URL;
    if (!url) throw new Error('DATABASE_URL tanımlı değil (canlı mod ve worker için gerekli).');
    globalForPrisma.prisma = new PrismaClient({ adapter: new PrismaPg({ connectionString: url }) });
  }
  return globalForPrisma.prisma;
}

export type { PrismaClient };
