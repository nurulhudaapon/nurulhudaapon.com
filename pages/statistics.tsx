import Link from 'next/link';

import Analytics from 'components/metrics/Analytics';
import Container from 'components/Container';
import GitHub from 'components/metrics/Github';
import YouTube from 'components/metrics/Youtube';

export default function Statistics() {
  return (
    <Container
      title="Stats – Nurul Huda (Apon)"
      description="A dashboard where I track my popularity on the internet."
    >
      <div className="mx-auto mb-16 flex max-w-2xl flex-col items-start justify-center">
        <h1 className="mb-4 text-3xl font-bold tracking-tight text-black dark:text-white md:text-5xl">
          Statistics
        </h1>
        <div className="mb-8">
          <p className="mb-4 text-gray-600 dark:text-gray-400">
            A dashboard where I track my popularity on the internet. Currently
            tracking all the blog post views on this site and my GitHub
            followers, more stats will be added in the future.
          </p>
        </div>
        <div className="my-2 grid w-full grid-cols-1 gap-4 sm:grid-cols-2">
          <Analytics />
          <GitHub />
        </div>
        <div className="flex w-full flex-col">
          <YouTube />
        </div>
      </div>
    </Container>
  );
}
