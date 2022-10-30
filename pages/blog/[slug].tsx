import { MDXRemote } from 'next-mdx-remote';
import BlogLayout from 'layouts/blog';
import Tweet from 'components/Tweet';
import components from 'components/MDXComponents';
import { getTweets } from 'lib/twitter';
import { mdxToHtml } from 'lib/mdx';
import { Post } from 'lib/types';
import { strapiClient } from 'lib/strapi';

export default function PostPage({ post }: { post: Post }) {
  const StaticTweet = ({ id } = {id: null}) => {
    const tweet = post.tweets.find((tweet) => tweet?.id === id) || {};
    return <Tweet {...tweet} />;
  };

  return (
    <BlogLayout post={post}>
      <MDXRemote
        {...post.content}
        components={
          {
            ...components,
            StaticTweet
          } as any
        }
      />
    </BlogLayout>
  );
}

export async function getStaticPaths() {
  const posts = await strapiClient.getPosts();

  return {
    paths: posts.map((p) => ({ params: { slug: p.attributes.slug } })),
    fallback: 'blocking'
  };
}

export async function getStaticProps({ params, preview = false }) {
  const posts = await strapiClient.getPostBySlug(params.slug);

  if (!posts?.length) return { notFound: true };
  const [postRaw] = posts;
  const post = postRaw.attributes;

  if (!post) {
    return { notFound: true };
  }


  const { html, tweetIDs, readingTime } = await mdxToHtml(post.content);
  const tweets = await getTweets(tweetIDs);

  return {
    props: {
      post: {
        ...post,
        content: html,
        tweets,
        readingTime
      }
    }
  };
}
