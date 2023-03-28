import components from 'components/MDXComponents';
import SnippetLayout from 'layouts/snippets';
import { apiService } from 'lib/api';
import { mdxToHtml } from 'lib/mdx';
import { Snippet } from 'lib/types';
import { MDXRemote } from 'next-mdx-remote';

export default function SnippetsPage({ snippet }: { snippet: Snippet }) {
    return (
        <SnippetLayout snippet={snippet}>
            <MDXRemote {...snippet.content} components={components} />
        </SnippetLayout>
    );
}

export async function getStaticPaths() {
    const snippets = await apiService.getSnippets();
    return {
        paths: snippets.map((snippet) => ({
            params: { slug: snippet.attributes.slug },
        })),
        fallback: 'blocking',
    };
}

export async function getStaticProps({ params, preview = false }) {
    const snippets = await apiService.getSnippetBySlug(params.slug);

    if (!snippets?.length) return { notFound: true };
    const [snippetRaw] = snippets;
    const snippet = snippetRaw.attributes;

    if (!snippet) {
        return { notFound: true };
    }

    const { html } = await mdxToHtml(snippet.content);

    return {
        props: {
            snippet: {
                ...snippet,
                content: html,
            },
        },
    };
}
