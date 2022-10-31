import { Post, Snippet, StrapiResponse } from "lib/types";
import { httpClient } from "./httpClient";

export const apiService = {
    // Post
    getPosts: async (...args) => (await httpClient<StrapiResponse<Post>>('/posts', ...args)).data,
    getSimplePosts: async () => (await httpClient<StrapiResponse<Post>>('/posts')).data,
    getPostBySlug: async (slug: string) => (await httpClient<StrapiResponse<Post>>('/posts', { filters: { slug: { $eq: slug } }, populate: ['imageUrl'] })).data,

    // Snippet
    getSnippets: async () => (await httpClient<StrapiResponse<Snippet>>('/snippets', { populate: ['logo'] })).data,
    getSnippetBySlug: async (slug: string) => (await httpClient<StrapiResponse<Snippet>>('/snippets', { filters: { slug: { $eq: slug } }, populate: ['logo'] })).data,
}
