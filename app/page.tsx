import Navigation from "../components/navs";

export default function Home() {
  return (
    <main className="h-[calc(100vh-3rem)] sm:h-[calc(100vh-6rem)] flex flex-col-reverse sm:flex-row items-center justify-center w-full max-w-4xl mx-auto px-4 gap-8 sm:gap-12">
      <div className="flex flex-col gap-4 sm:gap-6 items-center sm:items-start text-center sm:text-left sm:order-2 justify-center">
        <h1 className="text-4xl sm:text-6xl font-bold">Nurul Huda (Apon)</h1>
        <h2 className="text-xl sm:text-2xl font-medium text-neutral-300">
          Staff Engineer at <span className="font-semibold text-white">Voyage SMS</span>
        </h2>
        <div className="text-lg sm:text-xl text-neutral-400 max-h-[calc(100vh-20rem)] overflow-hidden">
          <div className="overflow-hidden">
            <span>A tech enthusiast, enrolling in Computer Science and Engineering at</span>
            <span className="font-semibold text-white"> Green University of Bangladesh</span> and working as a <span className="font-semibold text-white">Staff Engineer</span>
          </div>
        </div>
        <div className="flex flex-col items-center sm:items-start text-center sm:text-left sm:order-2 justify-center">
          <Navigation />
        </div>
      </div>
      <div className="flex-shrink-0 mb-4 sm:mb-0 sm:order-1">
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
