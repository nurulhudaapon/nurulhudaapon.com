import { MDXRemote } from 'next-mdx-remote';
import SnippetLayout from 'layouts/snippets';
import components from 'components/MDXComponents';
import { mdxToHtml } from 'lib/mdx';
import { Snippet } from 'lib/types';
import { strapiClient } from 'lib/strapi';

export default function SnippetsPage({ snippet }: { snippet: Snippet }) {
  return (
    <SnippetLayout snippet={snippet}>
      <MDXRemote {...snippet.content} components={components} />
    </SnippetLayout>
  );
}


export async function getStaticProps({ params, preview = false }) {
  const snippets = await strapiClient.getSnippetBySlug(params.slug);

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
        content: html
      }
    }
  };
}
