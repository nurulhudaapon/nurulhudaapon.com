import { serialize } from 'next-mdx-remote/serialize';
import readingTime from 'reading-time';
import remarkGfm from 'remark-gfm';
import rehypeSlug from 'rehype-slug';
import rehypeCodeTitles from 'rehype-code-titles';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import rehypePrism from 'rehype-prism-plus';

// TODO: Add more plugins
export async function mdxToHtml(source) {
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

    const tweetMatches = cleanedSource?.match(/<StaticTweet\sid="[0-9]+"\s\/>/g);
    const tweetIDs = tweetMatches?.map((tweet) => tweet.match(/[0-9]+/g)[0]);

    return {
        html: mdxSource,
        tweetIDs: tweetIDs || [],
        wordCount: cleanedSource?.split(/\s+/g).length,
        readingTime: readingTime(cleanedSource).text,
    };
}
