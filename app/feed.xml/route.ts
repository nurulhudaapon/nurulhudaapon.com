import { getAllPosts } from '@/libs';
import { NextResponse } from 'next/server';

export async function GET() {
  const posts = await getAllPosts();
  const baseUrl = process.env.NEXT_PUBLIC_BASE_URL;

  const rss = `<?xml version="1.0" encoding="UTF-8" ?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wfw="http://wellformedweb.org/CommentAPI/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>Nurul Huda (Apon)</title>
        <link>${baseUrl}</link>
        <description>A tech enthusiast, enrolling in Computer Science and Engineering at Green University of Bangladesh and working as a Staff Engineer</description>
        <language>en</language>
        <lastBuildDate>${new Date().toUTCString()}</lastBuildDate>
        <atom:link href="${baseUrl}/feed.xml" rel="self" type="application/rss+xml" />
        ${posts
          .map(
            (post) => `
          <item>
            <guid>${baseUrl}/blog/${post.slug}</guid>
            <title>${post.title}</title>
            <link>${baseUrl}/blog/${post.slug}</link>
            <description>${post.brief}</description>
            <pubDate>${new Date(post.publishedAt || '').toUTCString()}</pubDate>
            <author>${post.author.name}</author>
          </item>
        `,
          )
          .join('')}
      </channel>
    </rss>`;

  return new NextResponse(rss, {
    headers: {
      'Content-Type': 'application/xml',
      'Cache-Control': 'public, max-age=3600, s-maxage=3600',
    },
  });
}

export const revalidate = 3600;
