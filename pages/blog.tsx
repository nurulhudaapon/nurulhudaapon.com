import { SearchInput } from 'components/Input';
import { Suspense, useState } from 'react';

import BlogPost from 'components/BlogPost';
import Container from 'components/Container';
import { apiService } from 'lib/api';
import { InferGetStaticPropsType } from 'next';

export default function Blog({
  posts
}: InferGetStaticPropsType<typeof getStaticProps>) {
  const [searchValue, setSearchValue] = useState('');
  const filteredBlogPosts = posts.filter((post) =>
    JSON.stringify(post).toLowerCase().includes(searchValue.toLowerCase())
  );

  return (
    <Container
      title="Blog – Nurul Huda (Apon)"
      description="Writings on software development, study, personal life and more..."
    >
      <div className="flex flex-col items-start justify-center max-w-2xl mx-auto mb-16">
        <h1 className="mb-4 text-3xl font-bold tracking-tight text-black md:text-5xl dark:text-white">
          Blog
        </h1>
        <p className="mb-4 text-gray-600 dark:text-gray-400">
          {`Writings on software development, study, personal life and more. Subscribe to the newsletter to recieve notification when a new post is published.`}
        </p>
        <SearchInput setSearchValue={setSearchValue} />
        <Suspense fallback={null}>
          <h3 className="mt-8 mb-4 text-2xl font-bold tracking-tight text-black md:text-4xl dark:text-white">
            Posts
          </h3>
          {!filteredBlogPosts.length && (
            <p className="mb-4 text-gray-600 dark:text-gray-400">
              No posts found.
            </p>
          )}
          {filteredBlogPosts.map((post) => (
            <BlogPost
              key={post.title}
              slug={post.slug}
              title={post.title}
              excerpt={post.excerpt}
            />
          ))}
        </Suspense>
      </div>
    </Container>
  );
}

export async function getStaticProps({ preview = false }) {
  // const posts = await apiService.getPosts();
  const posts = [];
  return { props: { posts: posts?.map((p) => p.attributes) } };
}
