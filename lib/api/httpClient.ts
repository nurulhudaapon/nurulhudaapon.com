import qs from 'qs';
import { StrapiQuery } from './interfaces';
import { getAuthUrl, getUrl } from './utility';

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
