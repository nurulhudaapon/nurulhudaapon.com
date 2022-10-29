import { Suspense } from 'react';
import Image from 'next/image';
import Link from 'next/link';

import BlogPostCard from '../components/BlogPostCard';
import Container from '../components/Container';
import ProjectCard from 'components/ProjectCard';
import Subscribe from '../components/Subscribe';
import VideoCard from '../components/VideoCard';
import { CONTENT, GLOBAL_CONFIG } from 'components/Resources';

export default function Home() {
  return (
    <Suspense fallback={null}>
      <Container>
        <div className="flex flex-col justify-center items-start max-w-2xl border-gray-200 dark:border-gray-700 mx-auto pb-16">
          <ProfileSection />
          <ProjectSection />
          {GLOBAL_CONFIG.enableBlogSection && <BlogPostSection />}
          {GLOBAL_CONFIG.enableVideoSection && <VideoSection />}
          <br />
          <br />

          <Subscribe />
        </div>
      </Container>
    </Suspense>
  );
}

function ProfileSection({}) {
  return (
    <div className="flex flex-col-reverse sm:flex-row items-start">
      <div className="flex flex-col pr-8">
        <h1 className="font-bold text-3xl md:text-5xl tracking-tight mb-1 text-black dark:text-white">
          Nurul Huda (Apon)
        </h1>
        <h2 className="text-gray-700 dark:text-gray-200 mb-4">
          Software Engineer at <span className="font-semibold">Voyage SMS</span>
        </h2>
        <p className="text-gray-600 dark:text-gray-400 mb-16">
          A tech enthusiast, enrolling in Computer Science and Engineering at{' '}
          <span className="font-semibold">Green University of Bangladesh</span>{' '}
          and working as a{' '}
          <span className="font-semibold">Software Engineer</span>
        </p>
      </div>
      <div className="w-[100px] sm:w-[276px] relative mb-8 sm:mb-0 mr-auto">
        <Image
          alt="Nurul Huda (Apon)"
          height={200}
          width={200}
          src="/avatar.jpg"
          sizes="30vw"
          priority
          className={'rounded-full filter dark:grayscale'}
        />
      </div>
    </div>
  );
}

function ProjectSection({}) {
  return (
    <section>
      <h3 className="font-bold text-2xl md:text-4xl tracking-tight mb-6 text-black dark:text-white">
        Projects
      </h3>
      <div className="flex gap-6 flex-col md:flex-row mb-8">
        {CONTENT.projects.map((project) => (
          <ProjectCard key={project.repoUrl} {...project} />
        ))}
      </div>
    </section>
  );
}

function BlogPostSection({}) {
  return (
    <section>
      <h3 className="font-bold text-2xl md:text-4xl tracking-tight mb-6 text-black dark:text-white">
        Blog Posts
      </h3>
      <div className="flex gap-6 flex-col md:flex-row">
        {CONTENT.posts.map((post) => (
          <BlogPostCard key={post.slug} {...post} />
        ))}
      </div>
    </section>
  );
}

function VideoSection({}) {
  return (
    <section>
      <Link
        href="/blog"
        className="flex mt-8 text-gray-600 dark:text-gray-400 leading-7 rounded-lg hover:text-gray-800 dark:hover:text-gray-200 transition-all h-6"
      >
        Read all posts
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          className="h-6 w-6 ml-1"
        >
          <path
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M17.5 12h-15m11.667-4l3.333 4-3.333-4zm3.333 4l-3.333 4 3.333-4z"
          />
        </svg>
      </Link>

      <h3 className="font-bold text-2xl md:text-4xl tracking-tight mb-4 mt-16 text-black dark:text-white">
        Online videos
      </h3>
      <p className="text-gray-600 dark:text-gray-400 mb-4">Video details</p>

      <VideoCard
        index="04"
        href="https://www.youtube.com/watch?v=u8iv_yhSRI8&list=PL6bwFJ82M6FXgctyoWXqj7H0GK8_YIeF1&index=5"
        length="1:13:45"
        title="Firebase Admin with Next.js + SWR"
      />
      <a
        target="_blank"
        rel="noopener noreferrer"
        href="https://www.youtube.com/playlist?list=PL6bwFJ82M6FXgctyoWXqj7H0GK8_YIeF1"
        className="flex mt-8 text-gray-600 dark:text-gray-400 leading-7 rounded-lg hover:text-gray-800 dark:hover:text-gray-200 transition-all h-6"
      >
        Watch all videos
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          className="h-6 w-6 ml-1"
        >
          <path
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M17.5 12h-15m11.667-4l3.333 4-3.333-4zm3.333 4l-3.333 4 3.333-4z"
          />
        </svg>
      </a>
      <span className="h-16" />
    </section>
  );
}
