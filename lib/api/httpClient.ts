import qs from 'qs';
import { StrapiQuery } from './interfaces';
import { getUrl } from './utility';


/**
 * Helper to make GET requests to Strapi API endpoints
 * @returns Parsed API call response
 */
export async function httpClient(path, urlParamsObject: StrapiQuery = {}, options = {}) {
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
    const requestUrl = `${getUrl(
        `/api${path}${queryString ? `?${queryString}` : ""}`
    )}`;

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
