import Link from 'next/link';
import ExternalLink from './ExternalLink';

export default function Footer() {
  return (
    <footer className="flex flex-col justify-center items-start max-w-2xl mx-auto w-full mb-8">
      <hr className="w-full border-1 border-gray-200 dark:border-gray-800 mb-8" />
      <div className="w-full max-w-2xl grid grid-cols-1 gap-4 pb-16 sm:grid-cols-3">
        <div className="flex flex-col space-y-4">
          <Link
            href="/about"
            className="text-gray-500 hover:text-gray-600 transition"
          >
            About
          </Link>
          <Link
            href="/statistics"
            className="text-gray-500 hover:text-gray-600 transition"
          >
            Statistics
          </Link>
          <Link
            href="/snippets"
            className="text-gray-500 hover:text-gray-600 transition"
          >
            Code Snippets
          </Link>
        </div>
        <div className="flex flex-col space-y-4">
          <ExternalLink href="https://github.com/nurulhudaapon">
            GitHub
          </ExternalLink>
          <ExternalLink href="https://linkedin.com/nurulhudaapon">
            LinkedIn
          </ExternalLink>
        </div>
        <div className="flex flex-col space-y-4">
          <ExternalLink href="https://www.youtube.com/nurulhudaapon">
            YouTube
          </ExternalLink>
          <ExternalLink href="https://twitter.com/nurulhudaapon">
            Twitter
          </ExternalLink>
        </div>
      </div>
    </footer>
  );
}
