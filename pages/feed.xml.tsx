import RSS from 'rss';
import { apiService } from 'lib/api';

export async function getServerSideProps({ res }) {
  const feed = new RSS({
    title: 'Nurul Huda (Apon)',
    site_url: 'https://nurulhudaapon.com',
    feed_url: 'https://nurulhudaapon.com/feed.xml'
  });

  const allPosts = await apiService.getPosts();
  const posts = allPosts.map((post) => post.attributes);
  posts.map((post) => {
    feed.item({
      title: post.title,
      url: `https://nurulhudaapon.com/blog/${post.slug}`,
      date: post.date,
      description: post.excerpt
    });
  });

  res.setHeader('Content-Type', 'text/xml');
  res.setHeader(
    'Cache-Control',
    'public, s-maxage=1200, stale-while-revalidate=600'
  );
  res.write(feed.xml({ indent: true }));
  res.end();

  return {
    props: {}
  };
}

export default function RSSFeed() {
  return null;
}
