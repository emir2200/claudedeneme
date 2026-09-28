import 'dotenv/config';
import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
    seed: 'tsx prisma/seed.ts',
  },
  datasource: {
    // `prisma generate` URL gerektirmez; migrate/seed komutları için .env içinde tanımlayın.
    url: process.env.DATABASE_URL ?? '',
  },
});
