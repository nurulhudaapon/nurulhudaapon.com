import Image from 'next/image';
import { compileMDX } from 'next-mdx-remote/rsc';
import remarkGfm from 'remark-gfm';
import rehypeSlug from 'rehype-slug';
import rehypeCodeTitles from 'rehype-code-titles';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import rehypePrism from 'rehype-prism-plus';

function MdxImage({ src, alt }: { src?: string; alt?: string }) {
  if (!src) return null;
  return (
    <Image
      src={src}
      alt={alt || ''}
      width={800}
      height={600}
      className="rounded-lg my-4 w-full h-auto"
      sizes="(max-width: 768px) 100vw, 768px"
    />
  );
}

export async function mdxToHtml(source: string) {
  // Preserve query parameters while removing align attribute from markdown images
  let cleanedSource = source.replace(/!\[(.*?)\]\((.*?)(?:\s+align=["'][^"']*["'])?\)/g, (match, alt, src) => {
    if (src.includes('?')) {
      return `![${alt}](${src}&auto=compress,format&format=webp)`;
    }
    return `![${alt}](${src}?auto=compress,format&format=webp)`;
  });

  // Replace YouTube links of the form %[https://youtu.be/VIDEO_ID] or %[https://www.youtube.com/watch?v=VIDEO_ID] with responsive embed
  cleanedSource = cleanedSource.replace(
    /%\[(https?:\/\/(?:www\.)?(?:youtube\.com\/watch\?v=|youtu\.be\/)([\w-]+)[^\]]*)\]/g,
    (match, url, videoId) => {
      let id = videoId;
      if (id.includes('&')) id = id.split('&')[0];
      // Responsive full-width embed with 16:9 aspect ratio
      return `\n<div className=\"youtube-embed\"><iframe src=\"https://www.youtube.com/embed/${id}\" frameBorder=\"0\" allowFullScreen loading=\"lazy\"></iframe></div>\n`;
    },
  );

  const { content } = await compileMDX({
    source: cleanedSource,
    components: {
      img: MdxImage,
    },
    options: {
      parseFrontmatter: true,
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
      },
    },
  });

  return content;
}
