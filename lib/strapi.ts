import qs from 'qs';
import { GQL_QUERIES } from './api/graphql';
import { print } from 'graphql/language/printer';

class StrapiClient {

    hostUrl: string;
    authToken: string;

    constructor(hostUrl: string, authToken: string) {
        this.hostUrl = hostUrl;
        this.authToken = authToken;
    }

    async getSnippets() {
        console.log(print(GQL_QUERIES.GetSimplePosts));
        // console.log((await fetchAPI('/graphql', null, { method: 'POST', body: GQL_QUERIES.GetSimpleSnippets.loc.source.body })));
        return (await fetchAPI('/snippets', { populate: ['logo'] })).data;
    }

    async getPosts() {
        return (await fetchAPI('/posts')).data;
    }

    async getPostBySlug(slug: string) {
        return (await fetchAPI('/posts', { filters: { slug: { $eq: slug } }, populate: ['imageUrl'] })).data;
    }

    async getSnippetBySlug(slug: string) {
        return (await fetchAPI('/snippets', { filters: { slug: { $eq: slug } }, populate: ['logo'] })).data;
    }
}


interface StrapiQuery {
    sort?: string[];
    filters?: {
        slug: {
            $eq: string;
        };
    };
    populate?: string[];
    fields?: string[];
    pagination?: {
        pageSize: number;
        page: number;
    };
    publicationState?: string;
    locale?: string[];
}

/**
 * Get full Strapi URL from path
 * @param {string} path Path of the URL
 * @returns {string} Full Strapi URL
 */
export function getStrapiURL(path = "") {
    return `${process.env.NEXT_PUBLIC_STRAPI_API_URL
        }${path}`;
}

/**
 * Helper to make GET requests to Strapi API endpoints
 * @param {string} path Path of the API route
 * @param {Object} urlParamsObject URL params object, will be stringified
 * @param {Object} options Options passed to fetch
 * @returns Parsed API call response
 */
async function fetchAPI(path, urlParamsObject: StrapiQuery = {}, options: Partial<RequestInit> = {}) {
    // Merge default and user options
    const mergedOptions = {
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${process.env.NEXT_STRAPI_JWT_SECRET}`,

        },
        ...options,
    };

    // Build request URL
    const queryString = qs.stringify(urlParamsObject);
    let requestUrl = `${getStrapiURL(
        `/api${path}${queryString ? `?${queryString}` : ""}`
    )}`;

    if (path == '/graphql') requestUrl = `${getStrapiURL(`/graphql`)}`;

    // Trigger API call
    const response = await fetch(requestUrl, mergedOptions);

    // Handle response
    if (!response.ok) {
        console.error(response.statusText);
        throw new Error(`An error occured please try again: ${response.statusText}`);
    }
    const data = await response.json();
    return data;
}


export const strapiClient = new StrapiClient(process.env.NEXT_PUBLIC_STRAPI_API_URL, process.env.STRAPI_JWT_SECRET);


export function getStrapiMedia(media) {
    const { url } = media?.data?.attributes || {};
    const imageUrl = url?.startsWith("/") ? getStrapiURL(url) : url;
    return imageUrl;
}