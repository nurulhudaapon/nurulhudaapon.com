import { gqlClient } from '@/libs';
import { queries } from '@/libs';
import { mdxToHtml } from './util';
import PostContent from '../component';
import { PostResponse } from '../types';
import { Metadata } from 'next';
import { generateOGImage } from '@/libs/og';
import './blog.css';
import Link from 'next/link';

export async function generateStaticParams() {
  const response = await gqlClient(queries.getPosts)();
  const posts = response as { data: { publication: { posts: { edges: { node: { slug: string } }[] } } } };
  return posts.data.publication.posts.edges.map((post) => ({
    slug: post.node.slug,
  }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const slug = (await params).slug;
  const response = await gqlClient<PostResponse>(queries.getPostBySlug)({ slug });
  const post = response.data.publication.post;

  post.author = {
    name: 'Nurul Huda (Apon)',
  };
  await generateOGImage({ post, outputPath: `public/og/${post.slug}.png` });

  if (!post) {
    return {
      title: 'Post Not Found',
      description: 'The post you are looking for does not exist.',
    };
  }

  const ogImage = `/og/${post.slug}.png`;

  return {
    title: post.title,
    description: post.brief,
    metadataBase: new URL(process.env.NEXT_PUBLIC_BASE_URL),
    openGraph: {
      title: post.title,
      description: post.brief,
      type: 'article',
      publishedTime: post.publishedAt,
      authors: [post.author.name],
      images: [ogImage],
    },
    twitter: {
      card: 'summary_large_image',
      title: post.title,
      description: post.brief,
      images: [ogImage],
    },
  };
}

export default async function BlogPost({ params }: { params: Promise<{ slug: string }> }) {
  const slug = (await params).slug;
  const response = await gqlClient<PostResponse>(queries.getPostBySlug)({ slug });
  const post = response.data.publication.post;

  if (!post || !post.content) {
    return (
      <div className="w-full max-w-2xl space-y-8">
        <h1 className="text-4xl font-bold mb-4 text-black dark:text-white">Post Not Found</h1>
        <p className="text-lg text-neutral-600 dark:text-neutral-400">The post you're looking for doesn't exist.</p>
      </div>
    );
  }

  const mdx = await mdxToHtml(post.content.markdown);

  return (
    <div>
      <div className="flex items-center mb-4">
        <Link
          href="/blog"
          className="inline-flex items-center gap-2 py-2 text-sm font-medium text-neutral-600 dark:text-neutral-400 hover:text-black dark:hover:text-white transition-colors"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="w-4 h-4"
          >
            <path d="m12 19-7-7 7-7" />
            <path d="M19 12H5" />
          </svg>
          Back to Blog
        </Link>
      </div>
      <PostContent post={post} mdx={mdx} />
    </div>
  );
}
