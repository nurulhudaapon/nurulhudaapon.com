'use client';

import Link from 'next/link';

export default function NotFoundPage() {
  const currentFiveSeconds = Math.floor(Date.now() / 5000);
  const randomMessage = messages[currentFiveSeconds % messages.length];

  return (
    <div className="mx-auto grid place-items-center text-center px-8">
      <div className="flex flex-col items-center gap-4">
        <div className="w-20 h-20 mx-auto">
          {/* You might want to replace this with an actual icon component or SVG */}
          <svg className="w-full h-full" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path
              d="M12 2L2 7L12 12L22 7L12 2Z"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            <path
              d="M2 17L12 22L22 17"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
            <path
              d="M2 12L12 17L22 12"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </div>
        <p className="text-lg">{String(randomMessage)}</p>
        <p className="text-gray-600">
          You are not legally allowed to be here. Are you trying to hack something or what?
        </p>
        <div className="h-8" />

        <Link href="/">
          <button className="px-6 py-3 text-lg border rounded-lg hover:bg-gray-50 transition-colors">
            Return Home
          </button>
        </Link>
      </div>
    </div>
  );
}

const messages = [
  "I've no idea how you end up being somewhere that doesn't exist.",
  "It's quite puzzling how you've navigated to a page that isn't actually here.",
  "You've managed to find a spot that's off the map. How did you do that?",
  'This page seems to have dematerialized. Curious how you stumbled upon its former location.',
];
