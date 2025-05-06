import { gqlClient } from "@/libs";
import { queries } from "@/libs";
import { mdxToHtml } from './util';
import PostContent from './post';
import { PostResponse } from '../types';
import './blog.css';

export async function generateStaticParams() {
    const response = await gqlClient(queries.getPosts)();
    const posts = response as { data: { publication: { posts: { edges: { node: { slug: string } }[] } } } };
    return posts.data.publication.posts.edges.map((post) => ({
        slug: post.node.slug,
    }));
}

export default async function BlogPost({ params }: { params: Promise<{ slug: string }> }) {
    const slug = (await params).slug;
    const response = await gqlClient<PostResponse>(queries.getPostBySlug)({ slug });
    const post = response.data.publication.post;

    if (!post || !post.content) {
        return (
            <div className="w-full max-w-2xl space-y-8">
                <h1 className="text-4xl font-bold mb-4">Post Not Found</h1>
                <p className="text-lg text-neutral-400">The post you're looking for doesn't exist.</p>
            </div>
        );
    }

    const mdx = await mdxToHtml(post.content.markdown);

    return <PostContent post={post} mdx={mdx} />;
}
