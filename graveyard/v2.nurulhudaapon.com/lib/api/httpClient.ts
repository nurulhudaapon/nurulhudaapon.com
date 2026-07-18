import qs from 'qs';
import { StrapiQuery } from './interfaces';
import { getAuthUrl, getUrl } from './utility';
import { GQL_QUERIES } from './graphql';
import { DocumentNode, print } from 'graphql';

/**
 * Helper to make GET requests to Strapi API endpoints
 * @returns Parsed API call response
 */
export async function httpClient<T = unknown>(path, urlParamsObject: StrapiQuery = {}, options: RequestInit = {}, timeout: number = 8000) {
    const controller = new AbortController();
    const id = setTimeout(() => controller.abort(), timeout);

    // Merge default and user options
    const mergedOptions: RequestInit = {
        headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${getAuthUrl()}`,
        },
        signal: controller.signal,
        ...options,
    };

    // Build request URL
    const queryString = qs.stringify(urlParamsObject);
    const requestUrl = `${getUrl(`/api${path}${queryString ? `?${queryString}` : ''}`)}`;

    // Trigger API call
    const response = await fetch(requestUrl, mergedOptions);

    // Log Request for Dev
    if (process.env.NODE_ENV === 'development') {
        console.log(`Request: ${requestUrl}`);
        console.log(`Response: `, await response.clone().text());
        console.error('Status Code: ' + response.statusText);
    }
    // Handle response
    if (!response.ok) {
    }
    const data = (await response.json()) as T;
    return data;
}

export const gqlClient =
    <T = unknown>(query: TemplateStringsArray | DocumentNode) =>
    async (variables: Record<string, any> = {}) => {
        const queryStr = isDocumentNode(query) ? print(query) : query.join('');

        const response = await fetch(process.env.HASHNODE_GQL_URL, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                // Authorization: `Bearer ${getAuthUrl()}`,
            },
            body: JSON.stringify({ query: queryStr, variables }),
        });

        // Handle response
        if (!response.ok) {
        }
        const data = (await response.json()) as T;
        return data;
    };

const isDocumentNode = (query: any): query is DocumentNode => {
    return query.kind === 'Document';
}


// type GraphQlQueryResult<TData = any> = {
//     data?: TData;
//     errors?: Error[];
// };

// type QueryDefaultVariables = {
//     limit?: number;
//     offset?: number;
//     timezone?: string;
// };

// // type TypedDocumentNode<TData, TVariables> = typeof GQL_QUERIES;

// type GraphQlQueryProps<TData, TVariables> = {
//     operation: TypedDocumentNode<TData, TVariables> | string;
//     variables?: TVariables & QueryDefaultVariables;
//     signal?: AbortSignal;
// };

// export type GraphQlClientType = <TData, TVariables>(props: GraphQlQueryProps<TData, TVariables>) => Promise<GraphQlQueryResult<TData>>;
