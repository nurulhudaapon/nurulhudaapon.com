import Container from 'components/Container';
import Subscribe from 'components/Subscribe';

export default function Newsletter() {
  return (
    <Container
      title="Newsletter – Nurul Huda (Apon)"
      description="Thoughts on the software industry, programming, tech, videography, music, and my personal life."
    >
      <div className="flex flex-col items-start justify-center max-w-2xl mx-auto mb-16">
        <h1 className="mb-4 text-3xl font-bold tracking-tight text-black md:text-5xl dark:text-white">
          Newsletter
        </h1>
        <p className="mb-4 text-gray-600 dark:text-gray-400">
          Subscribe to my newsletter to get the latest updates on my blog posts,
          videos, and other things I'm working on. I'll also share any
          productivity tips, programming tips, and other things I find
          interesting.
        </p>
        <Subscribe />
      </div>
    </Container>
  );
}
