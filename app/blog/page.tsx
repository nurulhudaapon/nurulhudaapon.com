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
    <main className="flex flex-col items-center w-full max-w-4xl mx-auto py-24 px-4">
      <div className="w-full max-w-2xl space-y-8">
        <Navigation />

        <div className="space-y-12">
          <div>
            <h1 className="text-4xl font-bold mb-4">Blog</h1>
            <p className="text-lg text-neutral-400">
              Thoughts, ideas, and insights about software development, technology, and engineering practices.
            </p>
          </div>

          <div className="space-y-8">
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
                    {post.node.publishedAt && (
                      <ViewTransition name={`post-published-date-${post.node.id}`}>
                        <time dateTime={post.node.publishedAt} className="text-sm text-neutral-500">
                          {new Date(post.node.publishedAt).toLocaleDateString('en-US', {
                            year: 'numeric',
                            month: 'long',
                            day: 'numeric'
                          })}
                        </time>
                      </ViewTransition>
                    )}
                  </div>

                  <p className="text-neutral-400 mb-4">
                    {post.node.brief}
                  </p>
                  <div className="flex items-center gap-4 text-sm text-neutral-500">
                    <ViewTransition name={`post-readtime-${post.node.id}`}>
                      <span>{post.node.readTimeInMinutes} min read</span>
                    </ViewTransition>
                    <span>·</span>
                    <ViewTransition name={`post-views-${post.node.id}`}>
                      <span>{post.node.views} views</span>
                    </ViewTransition>
                    {post.node.subtitle && (
                      <>
                        <span>·</span>
                        <ViewTransition name={`post-subtitle-${post.node.id}`}>
                          <span>{post.node.subtitle}</span>
                        </ViewTransition>
                      </>
                    )}
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
