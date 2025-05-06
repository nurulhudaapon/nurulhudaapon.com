import Navigation from "../../components/navs";

export default function BlogLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <main className="flex flex-col items-center w-full max-w-4xl mx-auto py-4 sm:py-20 px-4">
      <div className="w-full max-w-3xl space-y-8">
        <Navigation />
        {children}
      </div>
    </main>
  );
} 