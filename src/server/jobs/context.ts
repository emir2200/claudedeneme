import type { PrismaClient } from '@/generated/prisma/client';
import type { Cache } from '../cache';
import type { Config } from '../config';

export interface Logger {
  info(message: string, extra?: Record<string, unknown>): void;
  warn(message: string, extra?: Record<string, unknown>): void;
  error(message: string, extra?: Record<string, unknown>): void;
}

export interface JobContext {
  prisma: PrismaClient;
  cache: Cache;
  config: Config;
  now: () => Date;
  log: Logger;
}

function line(level: string, message: string, extra?: Record<string, unknown>) {
  const payload = extra ? ` ${JSON.stringify(extra)}` : '';
  return `${new Date().toISOString()} ${level} ${message}${payload}`;
}

export const consoleLogger: Logger = {
  info: (m, e) => console.log(line('INFO ', m, e)),
  warn: (m, e) => console.warn(line('WARN ', m, e)),
  error: (m, e) => console.error(line('ERROR', m, e)),
};

export function errorInfo(err: unknown): Record<string, unknown> {
  return err instanceof Error ? { error: err.message } : { error: String(err) };
}

export function chunk<T>(xs: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += size) out.push(xs.slice(i, i + size));
  return out;
}
