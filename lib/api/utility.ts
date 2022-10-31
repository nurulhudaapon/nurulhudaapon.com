
export function getStrapiMedia(media) {
    const { url } = media?.data?.attributes || {};
    const imageUrl = url?.startsWith("/") ? getUrl(url) : url;
    return imageUrl;
}
export const getUrl = (path: string = "") => `${process.env.NEXT_PUBLIC_STRAPI_API_URL}${path}`;
