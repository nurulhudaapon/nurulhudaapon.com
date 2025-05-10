import { Post, PostsResponse } from '@/app/blog/types';
import { queries } from '.';
import { gqlClient } from './gql';

export async function getAllPosts(): Promise<Post[]> {
  const response = await gqlClient(queries.getPosts)();
  const posts = response as PostsResponse;
  const postsData = posts.data.publication.posts.edges;
  return postsData.map((post) => post.node);
}
