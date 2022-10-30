import Image from 'next/image';
import { parseISO, format } from 'date-fns';
import { PropsWithChildren, Suspense } from 'react';

import Container from 'components/Container';
import Subscribe from 'components/Subscribe';
import ViewCounter from 'components/ViewCounter';
import { Post } from 'lib/types';
import { getStrapiMedia } from 'lib/strapi';

export default function BlogLayout({
  children,
  post
}: PropsWithChildren<{ post: Post }>) {
  const imageUrl = post.imageUrl?.data?.id ? getStrapiMedia(post.imageUrl) : null;

  console.log(imageUrl);
  return (
    <Container
      title={`${post.title} – Nurul Huda (Apon)`}
      description={post.excerpt}
      image={imageUrl}
      date={new Date(post.publishedAt).toISOString()}
      type="article"
    >
      <article className="flex flex-col items-start justify-center w-full max-w-2xl mx-auto mb-16">
        <h1 className="mb-4 text-3xl font-bold tracking-tight text-black md:text-5xl dark:text-white">
          {post.title}
        </h1>
        <div className="flex flex-col items-start justify-between w-full mt-2 md:flex-row md:items-center">
          <div className="flex items-center">
            <Image
              alt="Nurul Huda (Apon)"
              height={24}
              width={24}
              sizes="20vw"
              src="/avatar.jpg"
              className="rounded-full"
            />
            <p className="ml-2 text-sm text-gray-700 dark:text-gray-300">
              {'Nurul Huda (Apon) / '}
              {format(parseISO(post.createdAt as string), 'MMMM dd, yyyy')}
            </p>
          </div>
          <p className="mt-2 text-sm text-gray-600 dark:text-gray-400 min-w-32 md:mt-0">
            {post.readingTime}
            {` • `}
            <ViewCounter slug={post.slug} />
          </p>
        </div>
        <Suspense fallback={null}>
          {imageUrl && (
            <Image
              alt={post.excerpt}
              height={620}
              width={620}
              sizes="20vw"
              src={imageUrl}
              className="w-full rounded-lg mt-6"
            />
          )}
          <div className="w-full mt-4 prose dark:prose-dark max-w-none">
            {children}
          </div>
          <div className="mt-8 w-full">
            <Subscribe />
          </div>
        </Suspense>
      </article>
    </Container>
  );
}
