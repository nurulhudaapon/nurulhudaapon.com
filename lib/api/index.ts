import { Post, Snippet, StrapiResponse } from 'lib/types';
import { GQL_QUERIES } from './graphql';
import { httpClient } from './httpClient';

export const apiService = {
    // Post
    getPosts: async (...args) => (await httpClient<StrapiResponse<Post>>('/posts', ...args)).data,
    getSimplePosts: async () => (await httpClient<StrapiResponse<Post>>('/posts')).data,
    getPostBySlug: async (slug: string) => (await httpClient<StrapiResponse<Post>>('/posts', { filters: { slug: { $eq: slug } }, populate: ['imageUrl'] })).data,

    // Snippet
    getSnippets: async () => (await httpClient<StrapiResponse<Snippet>>('/snippets', { populate: ['logo'] })).data,
    getSnippetBySlug: async (slug: string) => (await httpClient<StrapiResponse<Snippet>>('/snippets', { filters: { slug: { $eq: slug } }, populate: ['logo'] })).data,

    // User
    registerSubscriber: async ({ email }: { email: string }) =>
        await httpClient<{ jwt: string }>(
            '/auth/local/register',
            {},
            { method: 'POST', body: JSON.stringify({ email, username: email, password: email, confirmed: false, role: { connect: [3] } }) },
        ),
    getUsers: async () => await httpClient('/users'),
    getUserByEmail: async (email: string) => await httpClient<{ user: { email: string } }[]>(`/users`, { filters: { email: { $eq: email } } }),
    getUserCount: async () => await httpClient('/users/count'),

    // Question
    getQuestions: async () => await httpClient('/api/questions'),
    createQuestion: async ({ question, email, visitor }: { question: string; email: string; visitor: any }) =>
        await fetch('/api/questions', { method: 'POST', body: JSON.stringify({ question, email, visitor }) }),
};
