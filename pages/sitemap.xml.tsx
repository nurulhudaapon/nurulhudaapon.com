import { strapiClient } from 'lib/strapi';

const createSitemap = (slugs) => `<?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        ${slugs
          .map((slug) => {
            return `
                <url>
                    <loc>${`https://nurulhudaapon.com/${slug}`}</loc>
                </url>
            `;
          })
          .join('')}
    </urlset>
`;
export async function getServerSideProps({ res }) {
  const allPosts = await strapiClient.getPosts();
  const posts = allPosts.map((post) => post.attributes);  const allPages = [
    ...posts.map((slug) => `blog/${slug}`),
    ...[
      '',
      'about',
      'blog',
      'statistics',
      'newsletter',
      'snippets',
    ]
  ];

  res.setHeader('Content-Type', 'text/xml');
  res.setHeader(
    'Cache-Control',
    'public, s-maxage=1200, stale-while-revalidate=600'
  );
  res.write(createSitemap(allPages));
  res.end();

  return {
    props: {}
  };
}

export default function Sitemap() {
  return null;
}
