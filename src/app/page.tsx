import { Dashboard } from '@/components/dashboard/Dashboard';
import { describeError, getRankings } from '@/server/reports';

export const dynamic = 'force-dynamic';

export default async function Page() {
  try {
    return <Dashboard initialRankings={await getRankings()} initialError={null} />;
  } catch (err) {
    return <Dashboard initialRankings={null} initialError={describeError(err)} />;
  }
}
