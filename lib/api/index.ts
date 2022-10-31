import { httpClient } from "./httpClient";

export const apiService = {
    // Post
    getPosts: async () => (await httpClient('/posts')).data,
    getPostBySlug: async (slug: string) => (await httpClient('/posts', { filters: { slug: { $eq: slug } }, populate: ['imageUrl'] })).data,

    // Snippet
    getSnippets: async () => (await httpClient('/snippets', { populate: ['logo'] })).data,
    getSnippetBySlug: async (slug: string) => (await httpClient('/snippets', { filters: { slug: { $eq: slug } }, populate: ['logo'] })).data,
}
