import useSWR from 'swr';

import fetcher from 'lib/fetcher';
import { GitHub } from 'lib/types';
import MetricCard from 'components/metrics/Card';

export default function GitHubCard() {
  const { data } = useSWR<GitHub>('/api/github', fetcher);

  const followers = new Number(data?.followers);
  const link = 'https://github.com/nurulhudaapon';

  return (
    <MetricCard
      header="GitHub followers"
      link={link}
      metric={followers}
      isCurrency={false}
    />
  );
}
