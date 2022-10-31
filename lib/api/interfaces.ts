
export interface StrapiQuery {
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
