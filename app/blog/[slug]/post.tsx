'use client';

import { unstable_ViewTransition as ViewTransition } from 'react';
import { Post } from '../types';
import Image from 'next/image';

interface PostContentProps {
    post: Post;
    mdx: React.ReactNode;
}

export default function PostContent({ post, mdx }: PostContentProps) {
    const publishedDate = post.publishedAt ? new Date(post.publishedAt).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    }) : null;

    return (
        <article className="prose prose-invert max-w-none">
            <header className="mb-8">
                <ViewTransition name={`post-title-${post.id}`}>
                    <h1 className="text-4xl font-bold mb-4">
                        {post.title}
                    </h1>
                </ViewTransition>
                {post.coverImage && (
                    <div className="relative w-full aspect-[2/1] mb-8 rounded-xl overflow-hidden">
                        <img
                            src={post.coverImage.url}
                            alt={post.title}
                            className="object-cover"
                        />
                    </div>
                )}
                {post.subtitle && (
                    <ViewTransition name={`post-subtitle-${post.id}`}>
                        <h2 className="text-xl text-neutral-400 mb-4">
                            {post.subtitle}
                        </h2>
                    </ViewTransition>
                )}

                <div className="flex items-center gap-4 text-sm text-neutral-500">
                    {publishedDate && (
                        <>
                            <ViewTransition name={`post-published-date-${post.id}`}>
                                <time dateTime={post.publishedAt}>{publishedDate}</time>
                            </ViewTransition>
                            <span>·</span>
                        </>
                    )}

                    <ViewTransition name={`post-readtime-${post.id}`}>
                        <span>{post.readTimeInMinutes} min read</span>
                    </ViewTransition>
                    <span>·</span>

                    <ViewTransition name={`post-views-${post.id}`}>
                        <span>{post.views} views</span>
                    </ViewTransition>
                </div>
            </header>

            <ViewTransition name={`post-content-${post.id}`}>
                {mdx}
            </ViewTransition>
        </article>
    );
} 