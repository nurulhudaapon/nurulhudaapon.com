import { gqlClient } from '@/libs';
import { queries } from '@/libs';
import { mdxToHtml } from './util';
import PostContent from '../component';
import { PostResponse } from '../types';
import { Metadata } from 'next';
import { generateOGImage } from '@/libs/og';
import './blog.css';

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
    metadataBase: new URL('https://next.nuhu.dev'),
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

  return <PostContent post={post} mdx={mdx} />;
}
