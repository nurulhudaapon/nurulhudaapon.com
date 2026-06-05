import { ViewTransition } from 'react';
import Link from 'next/link';
import { getAllPosts } from '@/libs';
import { BlogPostMeta } from './component';
import { Metadata } from 'next';
import { NewsletterSubscribe } from '../components/newsletter-subscribe';

export const metadata: Metadata = {
  title: 'NH | Blog',
  description: 'All blogs from Nurul Huda (Apon)',
};

export default async function Blog() {
  const posts = await getAllPosts();

  return (
    <div className="space-y-8">
      <NewsletterSubscribe />

      <div className="space-y-4 sm:space-y-8">
        {posts.map((post) => (
          <article key={post.id} className="group">
            <Link href={`/blog/${post.slug}`} className="block">
              <div className="flex justify-between items-start mb-2">
                <ViewTransition name={`post-title-${post.id}`}>
                  <h2 className="text-2xl font-semibold text-black dark:text-white group-hover:text-neutral-600 dark:group-hover:text-neutral-200 transition">
                    {post.title}
                  </h2>
                </ViewTransition>
              </div>

              <ViewTransition name={`post-${post.subtitle ? 'subtitle' : 'content'}-${post.id}`}>
                <p className="text-neutral-600 dark:text-neutral-300 mb-4 line-clamp-2">
                  {post.subtitle || post.brief}
                </p>
              </ViewTransition>
              <BlogPostMeta post={{ node: post }} />
            </Link>
          </article>
        ))}
      </div>
    </div>
  );
}

export async function generateStaticParams() {
  const posts = await getAllPosts();
  return posts.map((post) => ({
    slug: post.slug,
  }));
}
