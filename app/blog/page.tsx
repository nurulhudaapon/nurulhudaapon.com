import { unstable_ViewTransition as ViewTransition } from 'react';
import Link from 'next/link';
import { gqlClient } from '@/libs';
import { queries } from '@/libs';
import { PostsResponse } from './types';
import { BlogPostMeta } from './component';

export default async function Blog() {
  const response = await gqlClient(queries.getPosts)();
  const posts = response as PostsResponse;
  const postsData = posts.data.publication.posts.edges;

  return (
    <div className="space-y-8">
      <div className="space-y-4 sm:space-y-8">
        {postsData.map((post) => (
          <article key={post.node.id} className="group">
            <Link href={`/blog/${post.node.slug}`} className="block">
              <div className="flex justify-between items-start mb-2">
                <ViewTransition name={`post-title-${post.node.id}`}>
                  <h2 className="text-2xl font-semibold text-black dark:text-white group-hover:text-neutral-600 dark:group-hover:text-neutral-200 transition">
                    {post.node.title}
                  </h2>
                </ViewTransition>
              </div>

              <ViewTransition name={`post-${post.node.subtitle ? 'subtitle' : 'content'}-${post.node.id}`}>
                <p className="text-neutral-600 dark:text-neutral-300 mb-4 line-clamp-2">
                  {post.node.subtitle || post.node.brief}
                </p>
              </ViewTransition>
              <BlogPostMeta post={post} />
            </Link>
          </article>
        ))}
      </div>
    </div>
  );
}

export async function generateStaticParams() {
  const response = await gqlClient(queries.getPosts)();
  const posts = response as PostsResponse;
  return posts.data.publication.posts.edges.map((post) => ({
    slug: post.node.slug,
  }));
}
