import { Post } from '@/app/blog/types';

const GITHUB_OWNER = 'nurulhudaapon';
const GITHUB_REPO = 'blogs';
const GITHUB_BRANCH = 'main';

const AUTHOR_NAME = 'Nurul Huda (Apon)';

interface GitHubTreeItem {
  path: string;
  type: 'blob' | 'tree';
  size?: number;
}

interface GitHubTreeResponse {
  tree: GitHubTreeItem[];
}

interface Frontmatter {
  title?: string;
  seoTitle?: string;
  seoDescription?: string;
  datePublished?: string;
  cuid?: string;
  slug?: string;
  subtitle?: string;
  cover?: string;
  ogImage?: string;
  tags?: string;
}

const githubHeaders = (): HeadersInit => {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'nurulhudaapon.com',
  };
  // Optional token raises GitHub's rate limit from 60 to 5000 req/hr during build.
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }
  return headers;
};

/** Parse the simple flat YAML frontmatter Hashnode exports. */
function parseFrontmatter(raw: string): { data: Frontmatter; content: string } {
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/.exec(raw);
  if (!match) return { data: {}, content: raw };

  const data: Record<string, string> = {};
  for (const line of match[1].split(/\r?\n/)) {
    const sep = line.indexOf(':');
    if (sep === -1) continue;
    const key = line.slice(0, sep).trim();
    if (!key) continue;
    let value = line.slice(sep + 1).trim();
    // Strip surrounding quotes if present.
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    data[key] = value;
  }

  return { data: data as Frontmatter, content: match[2] };
}

const WORDS_PER_MINUTE = 200;

function readTimeInMinutes(content: string): number {
  const words = content.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / WORDS_PER_MINUTE));
}

/** Build a plain-text excerpt from the markdown body. */
function buildBrief(content: string): string {
  const text = content
    .replace(/```[\s\S]*?```/g, '') // code blocks
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '') // images
    .replace(/%\[[^\]]*\]/g, '') // hashnode embeds
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1') // links -> text
    .replace(/[#>*_`~-]/g, '') // markdown punctuation
    .replace(/\s+/g, ' ')
    .trim();
  return text.length > 240 ? `${text.slice(0, 240).trimEnd()}…` : text;
}

function toPost(data: Frontmatter, content: string): Post | null {
  if (!data.slug || !data.title) return null;

  return {
    id: data.cuid || data.slug,
    coverImage: data.cover ? { url: data.cover } : null,
    slug: data.slug,
    subtitle: data.subtitle || null,
    views: 0,
    title: data.title,
    brief: data.seoDescription || buildBrief(content),
    url: `https://nurulhudaapon.com/blog/${data.slug}`,
    readTimeInMinutes: readTimeInMinutes(content),
    publishedAt: data.datePublished ? new Date(data.datePublished).toISOString() : undefined,
    content: { markdown: content },
    author: { name: AUTHOR_NAME },
  };
}

async function listMarkdownPaths(): Promise<string[]> {
  const res = await fetch(
    `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/trees/${GITHUB_BRANCH}?recursive=1`,
    { headers: githubHeaders() },
  );
  if (!res.ok) {
    throw new Error(`GitHub tree fetch failed: ${res.status} ${res.statusText}`);
  }
  const tree = (await res.json()) as GitHubTreeResponse;
  return tree.tree
    .filter((item) => item.type === 'blob' && item.path.endsWith('.md'))
    .filter((item) => !item.path.split('/').pop()!.startsWith('draft-'))
    .map((item) => item.path);
}

async function fetchMarkdown(filePath: string): Promise<string> {
  const res = await fetch(
    `https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${filePath}`,
    { headers: { 'User-Agent': 'nurulhudaapon.com' } },
  );
  if (!res.ok) {
    throw new Error(`GitHub raw fetch failed for ${filePath}: ${res.status}`);
  }
  return res.text();
}

let postsCache: Promise<Post[]> | null = null;

/** Fetch and parse all (non-draft) posts, newest first. Cached per build process. */
export async function getAllPosts(): Promise<Post[]> {
  if (postsCache) return postsCache;

  postsCache = (async () => {
    const paths = await listMarkdownPaths();
    const raws = await Promise.all(paths.map(fetchMarkdown));
    const posts = raws
      .map((raw) => {
        const { data, content } = parseFrontmatter(raw);
        return toPost(data, content);
      })
      .filter((p): p is Post => p !== null);

    posts.sort((a, b) => {
      const da = a.publishedAt ? Date.parse(a.publishedAt) : 0;
      const db = b.publishedAt ? Date.parse(b.publishedAt) : 0;
      return db - da;
    });

    return posts;
  })();

  return postsCache;
}

export async function getPostBySlug(slug: string): Promise<Post | null> {
  const posts = await getAllPosts();
  return posts.find((p) => p.slug === slug) ?? null;
}
