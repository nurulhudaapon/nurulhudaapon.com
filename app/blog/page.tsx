import Navigation from "../../components/navs";
import { unstable_ViewTransition as ViewTransition } from 'react'
import Link from "next/link";
import { gqlClient } from "@/libs";
import { queries } from "@/libs";
import { Post, PostsResponse } from './types';

export default async function Blog() {
  const response = await gqlClient(queries.getPosts)();
  const posts = response as PostsResponse;
  const postsData = posts.data.publication.posts.edges;

  return (
    <main className="flex flex-col items-center w-full max-w-4xl mx-auto py-4 sm:py-20 px-4">
      <div className="w-full max-w-2xl space-y-4">
        <Navigation />

        <div className="space-y-8">
          <div className="space-y-4 sm:space-y-8">
            {postsData.map((post) => (
              <article key={post.node.id} className="group">
                <Link href={`/blog/${post.node.slug}`} className="block">
                  <div className="flex justify-between items-start mb-2">
                    <ViewTransition name={`post-title-${post.node.id}`}>
                      <h2
                        className="text-2xl font-semibold group-hover:text-neutral-300 transition"
                      >
                        {post.node.title}
                      </h2>
                    </ViewTransition>
                  </div>

                  <ViewTransition name={`post-${post.node.subtitle ? 'subtitle' : 'content'}-${post.node.id}`}>
                    <p className="text-neutral-400 mb-4 line-clamp-2">
                      {post.node.subtitle || post.node.brief}
                    </p>
                  </ViewTransition>
                  <div className="flex items-center gap-4 text-sm text-neutral-500">
                    {post.node.publishedAt && (
                      <ViewTransition name={`post-published-date-${post.node.id}`}>
                        <time dateTime={post.node.publishedAt} className="text-sm text-neutral-500 order-1 sm:order-none">
                          {new Date(post.node.publishedAt).toLocaleDateString('en-US', {
                            year: 'numeric',
                            month: 'short',
                            day: 'numeric'
                          })}
                        </time>
                      </ViewTransition>
                    )}
                    <span className="order-2 sm:order-none">·</span>
                    <ViewTransition name={`post-readtime-${post.node.id}`}>
                      <span className="order-3 sm:order-none">{post.node.readTimeInMinutes} min read</span>
                    </ViewTransition>
                    <span className="order-4 sm:order-none">·</span>
                    <ViewTransition name={`post-views-${post.node.id}`}>
                      <span className="order-5 sm:order-none">{post.node.views} views</span>
                    </ViewTransition>
                  </div>
                </Link>
              </article>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
} 

export async function generateStaticParams() {
  const response = await gqlClient(queries.getPosts)();
  const posts = response as PostsResponse;
  return posts.data.publication.posts.edges.map((post) => ({
    slug: post.node.slug,
  }));
}
