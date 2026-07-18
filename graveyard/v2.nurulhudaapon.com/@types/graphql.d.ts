type GqlQueryNames = 'SubscribeToNewsletter' | 'GetPostBySlug' | 'GetPosts';

declare module '*.gql' {
    import { DocumentNode } from 'graphql';
    const Schema: DocumentNode & Record<GqlQueryNames, DocumentNode>;

    export = Schema;
}
