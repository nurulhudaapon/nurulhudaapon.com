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
      <div className="flex flex-col justify-center items-start max-w-2xl mx-auto mb-16">
        <h1 className="font-bold text-3xl md:text-5xl tracking-tight mb-4 text-black dark:text-white">
          Statistics
        </h1>
        <div className="mb-8">
          <p className="text-gray-600 dark:text-gray-400 mb-4">
            A dashboard where I track my popularity on the internet. Currently tracking all the blog post views on this site and my GitHub followers, more stats will be added in the future.
          </p>
        </div>
        <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 my-2 w-full">
          <Analytics />
          <GitHub />
        </div>
        {/* <div className="flex flex-col w-full">
          <YouTube />
        </div> */}
      </div>
    </Container>
  );
}
