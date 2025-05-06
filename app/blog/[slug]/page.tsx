import Navigation from "../../../components/navs";
import { gqlClient } from "@/libs";
import { queries } from "@/libs";
import { mdxToHtml } from './util';
import PostContent from './post';
import { PostResponse } from '../types';

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
            <main className="flex flex-col items-center w-full max-w-4xl mx-auto py-4 sm:py-20 px-4">
                <div className="w-full max-w-2xl space-y-8">
                    <Navigation />
                    <h1 className="text-4xl font-bold mb-4">Post Not Found</h1>
                    <p className="text-lg text-neutral-400">The post you're looking for doesn't exist.</p>
                </div>
            </main>
        );
    }

    const mdx = await mdxToHtml(post.content.markdown);

    return (
        <main className="flex flex-col items-center w-full max-w-4xl mx-auto py-4 sm:py-20 px-4">
            <div className="w-full max-w-2xl space-y-8">
                <Navigation />
                <PostContent post={post} mdx={mdx} />
            </div>
        </main>
    );
}
