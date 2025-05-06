import Navigation from "../components/navs";

const posts = [
  {
    id: 1,
    title: "Building Scalable Applications with .NET Core",
    excerpt: "Learn how to build robust and scalable applications using .NET Core, focusing on best practices and modern architecture patterns.",
    date: "2024-03-15",
    readTime: "5 min read"
  },
  {
    id: 2,
    title: "TypeScript Best Practices for React Developers",
    excerpt: "A comprehensive guide to using TypeScript effectively in React applications, covering type safety, interfaces, and advanced patterns.",
    date: "2024-03-10",
    readTime: "7 min read"
  },
  {
    id: 3,
    title: "PostgreSQL Performance Optimization Tips",
    excerpt: "Essential tips and tricks for optimizing PostgreSQL database performance, including indexing strategies and query optimization.",
    date: "2024-03-05",
    readTime: "6 min read"
  }
];

export default function Blog() {
  return (
    <main className="flex flex-col items-center w-full max-w-4xl mx-auto py-24 px-4">
      <div className="w-full max-w-2xl space-y-8">
        <Navigation />
        
        <div className="space-y-12">
          <div>
            <h1 className="text-4xl font-bold mb-4">Blog</h1>
            <p className="text-lg text-neutral-400">
              Thoughts, ideas, and insights about software development, technology, and engineering practices.
            </p>
          </div>

          <div className="space-y-8">
            {posts.map((post) => (
              <article key={post.id} className="group">
                <a href={`/blog/${post.id}`} className="block">
                  <h2 className="text-2xl font-semibold mb-2 group-hover:text-neutral-300 transition">
                    {post.title}
                  </h2>
                  <p className="text-neutral-400 mb-4">
                    {post.excerpt}
                  </p>
                  <div className="flex items-center gap-4 text-sm text-neutral-500">
                    <time dateTime={post.date}>{post.date}</time>
                    <span>·</span>
                    <span>{post.readTime}</span>
                  </div>
                </a>
              </article>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
} 