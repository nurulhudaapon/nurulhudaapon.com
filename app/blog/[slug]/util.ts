import { serialize } from 'next-mdx-remote/serialize';
import remarkGfm from 'remark-gfm';
import rehypeSlug from 'rehype-slug';
import rehypeCodeTitles from 'rehype-code-titles';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import rehypePrism from 'rehype-prism-plus';

export async function mdxToHtml(source: string) {
    // Preserve query parameters while removing align attribute from markdown images
    const cleanedSource = source.replace(/!\[(.*?)\]\((.*?)(?:\s+align=["'][^"']*["'])?\)/g, (match, alt, src) => {
        // If src already has query params, append format and auto
        if (src.includes('?')) {
            return `![${alt}](${src}&auto=compress,format&format=webp)`;
        }
        // If no query params, add them with ?
        return `![${alt}](${src}?auto=compress,format&format=webp)`;
    });

    const mdxSource = await serialize(cleanedSource, {
        mdxOptions: {
            remarkPlugins: [remarkGfm],
            rehypePlugins: [
                rehypeSlug,
                rehypeCodeTitles,
                rehypePrism,
                [
                    rehypeAutolinkHeadings,
                    {
                        properties: {
                            className: ['anchor'],
                        },
                    },
                ],
            ],
            format: 'mdx',
        },
    });


    return mdxSource;
}