import Navigation from '../components/navs';

export default function Home() {
  return (
    <main className="flex flex-col-reverse sm:flex-row items-center justify-center w-full max-w-4xl mx-auto px-4 gap-8 sm:gap-12">
      <div className="flex flex-col gap-4 sm:gap-6 items-center sm:items-start text-center sm:text-left sm:order-2 justify-center">
        <h1 className="text-4xl sm:text-6xl font-bold">Nurul Huda (Apon)</h1>
        <h2 className="text-xl sm:text-2xl font-medium text-neutral-600 dark:text-neutral-300">
          Staff Engineer at{' '}
          <a href="https://vyg.ai" target="_blank" rel="noopener noreferrer">
            <span className="font-semibold text-black dark:text-white">Voyage Mobile Inc.</span>
          </a>
        </h2>
        <div className="text-lg sm:text-xl text-neutral-500 dark:text-neutral-400 max-h-[calc(100vh-20rem)] overflow-hidden">
          <div className="overflow-hidden">
            <span>A tech enthusiast, enrolling in Computer Science and Engineering at</span>
            <a href="https://green.edu.bd" target="_blank" rel="noopener noreferrer">
              <span className="font-semibold text-black dark:text-white"> Green University of Bangladesh</span>
            </a>{' '}
            and working as a <span className="font-semibold text-black dark:text-white">Staff Engineer</span>
          </div>
        </div>
        <div className="flex flex-col items-center sm:items-start text-center sm:text-left sm:order-2 justify-center">
          <Navigation />
        </div>
      </div>
      <div className="flex-shrink-0 mb-4 sm:mb-0 sm:order-1">
        <img
          src="/nurulhudaapon.webp"
          alt="Nurul Huda (Apon)"
          width={280}
          fetchPriority="high"
          height={280}
          className="rounded-full object-cover dark:grayscale border-4 border-neutral-200 dark:border-neutral-800 mx-auto"
        />
      </div>
    </main>
  );
}
