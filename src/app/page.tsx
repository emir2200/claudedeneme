import { Dashboard } from '@/components/dashboard/Dashboard';
import { getDashboardSnapshot } from '@/server/snapshot/getSnapshot';

export const dynamic = 'force-dynamic';

export default async function Page() {
  const snapshot = await getDashboardSnapshot();
  return <Dashboard initial={snapshot} />;
}
