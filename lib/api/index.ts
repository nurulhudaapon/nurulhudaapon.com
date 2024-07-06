import { Post, Snippet, StrapiResponse } from 'lib/types';
import { GQL_QUERIES } from './graphql';
import { gqlClient, httpClient } from './httpClient';

export const apiService = {
    // Post
    // getPosts: async (...args) => (await httpClient<StrapiResponse<Post>>('/posts', ...args)).data,
    getPosts: async () => {
        const posts = await gqlClient(GQL_QUERIES.GetPosts)({});
        // console.log(JSON.stringify(posts?.data?.publication?.posts, null, 2));
        const formattedPosts = posts?.data?.publication?.posts?.edges?.map((edge) => edge.node);
        console.log(JSON.stringify(formattedPosts, null, 2));
        return formattedPosts;
    },
    getSimplePosts: async () => (await httpClient<StrapiResponse<Post>>('/posts')).data,
    getPostBySlug: async (slug: string) => {
        const post = await gqlClient(GQL_QUERIES.GetPostBySlug)({ slug });
        const formattedPosts = post?.data?.publication?.post;
        console.log(post, JSON.stringify(formattedPosts, null, 2));
        return formattedPosts;
    },

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
    subscribeToNewsletter: async ({ email }: { email: string }) => {
        const subscription = await gqlClient(GQL_QUERIES.SubscribeToNewsletter)({ email });
        console.log(subscription);
        return subscription;
    },

    // Question
    getQuestions: async () => (await fetch('/api/questions')).json() as Promise<any[]>,
    createQuestion: async ({ question, email, visitor }: { question: string; email: string; visitor: any }) =>
        await fetch('/api/questions', { method: 'POST', body: JSON.stringify({ question, email, visitor }) }),
    getAllQuestions: async () => (await fetch('/api/questions?all=true')).json() as Promise<any[]>,
    updateQuestion: async ({ id, answer, deleted }: { id: string; answer?: string; deleted?: boolean }) =>
        await fetch(`/api/questions`, { method: 'PUT', body: JSON.stringify({ answer, id, deleted }) }),
};
