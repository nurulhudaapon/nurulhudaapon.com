'use client';

import { PostEdge } from './types';
import { ViewTransition } from 'react';

import { Post } from './types';

interface PostContentProps {
  post: Post;
  mdx: React.ReactNode;
}

export default function PostContent({ post, mdx }: PostContentProps) {
  const publishedDate = post.publishedAt
    ? new Date(post.publishedAt).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      })
    : null;

  return (
    <article className="max-w-none">
      <header className="mb-3">
        <ViewTransition name={`post-title-${post.id}`}>
          <h1 className="text-4xl font-bold mb-4 text-black dark:text-white">{post.title}</h1>
        </ViewTransition>
        {post.coverImage && (
          <div className="relative w-full mb-4 rounded-xl overflow-hidden">
            <img src={post.coverImage.url} alt={post.title} className="object-cover" />
          </div>
        )}
        {post.subtitle && (
          <ViewTransition name={`post-subtitle-${post.id}`}>
            <h2 className="text-xl text-neutral-600 dark:text-neutral-400 mb-4">{post.subtitle}</h2>
          </ViewTransition>
        )}

        <BlogPostMeta post={{ node: post }} />
      </header>

      <ViewTransition name={`post-content-${post.id}`}>
        <div className="prose dark:prose-invert max-w-none">{mdx}</div>
      </ViewTransition>
    </article>
  );
}

export function BlogPostMeta({ post }: { post: PostEdge }) {
  return (
    <ViewTransition name={`post-meta-${post.node.id}`}>
      <div className="flex items-center gap-4 text-sm text-neutral-500 dark:text-neutral-400">
        {post.node.publishedAt && (
          <time
            dateTime={post.node.publishedAt}
            className="text-sm text-neutral-500 dark:text-neutral-400 order-1 sm:order-none"
          >
            {new Date(post.node.publishedAt).toLocaleDateString('en-US', {
              year: 'numeric',
              month: 'short',
              day: 'numeric',
            })}
          </time>
        )}
        <span className="order-2 sm:order-none">·</span>
        <span className="order-3 sm:order-none">{post.node.readTimeInMinutes} min read</span>
        {/* <span className="order-4 sm:order-none">·</span> */}
        {/* <span className="order-5 sm:order-none">{post.node.views} views</span> */}
      </div>
    </ViewTransition>
  );
}
