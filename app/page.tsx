import Navigation from "../components/navs";

export default function Home() {
  return (
    <main className="flex flex-col-reverse sm:flex-row items-center justify-between w-full max-w-4xl mx-auto py-24 px-4 gap-12">
      <div className="flex-1 flex flex-col gap-4 sm:gap-6 items-center sm:items-start text-center sm:text-left sm:order-2">
        <h1 className="text-4xl sm:text-6xl font-bold">Nurul Huda (Apon)</h1>
        <h2 className="text-xl sm:text-2xl font-medium text-neutral-300">
          Staff Engineer at <span className="font-semibold text-white">Voyage SMS</span>
        </h2>
        <p className="text-lg sm:text-xl text-neutral-400">
          A tech enthusiast, enrolling in Computer Science and Engineering at
          <span className="font-semibold text-white"> Green University of Bangladesh</span> and working as a <span className="font-semibold text-white">Staff Engineer</span>
        </p>
        <div className="w-full flex flex-col items-center sm:items-start gap-4 mt-6">
          <Navigation />
        </div>
      </div>
      <div className="flex-shrink-0 mb-8 sm:mb-0 sm:order-1">
        <img
          src="/nurulhudaapon.jpeg"
          alt="Nurul Huda (Apon)"
          width={250}
          height={250}
          className="rounded-full object-cover grayscale border-4 border-neutral-800 mx-auto"
        />
      </div>
    </main>
  );
}
