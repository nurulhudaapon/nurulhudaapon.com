import Navigation from "../components/navs";

export default function About() {
  return (
    <main className="flex flex-col items-center w-full max-w-4xl mx-auto py-24 px-4">
      <div className="w-full max-w-2xl space-y-8">
        <Navigation />
        
        <div className="space-y-6">
          <p className="text-lg text-neutral-400">
            Hello, I'm Nurul. I'm a Staff Engineer at Voyage SMS, where I build stuff using C#, .NET Core, React, TypeScript, PostgreSQL and many more. I'm also a Computer Science and Engineering student at Green University of Bangladesh.
          </p>

          <p className="text-lg text-neutral-400">
            Currently, I'm working as a Staff Engineer at Voyage SMS, where I focus on building robust and scalable solutions using modern technologies.
          </p>

          <p className="text-lg text-neutral-400">
            I'm currently pursuing my Bachelor's degree in Computer Science and Engineering at Green University of Bangladesh, with an expected graduation in 2026. This academic journey complements my professional experience, allowing me to stay at the forefront of technological advancements.
          </p>
        </div>
      </div>
    </main>
  );
}
