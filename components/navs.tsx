'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ViewTransition } from 'react';
import React from 'react';

const navItems: NavItemData[] = [
  { href: '/', label: 'Home' },
  { href: '/blog', label: 'Blog' },
  { href: '/about', label: 'About' },
  { href: 'https://nuhu.dev', label: 'Dev', isExternal: true },
];

export default function Navigation() {
  return (
    <div className="sticky top-0 z-50 py-3 bg-white/80 dark:bg-neutral-950/80 backdrop-blur-sm w-full">
      <ViewTransition name="navigation">
        <nav className="flex gap-3 sm:gap-5 text-base sm:text-lg font-medium">
          {navItems.map((item) => (
            <NavItem key={item.href} href={item.href} label={item.label} isExternal={item.isExternal}>
              {item.label}
            </NavItem>
          ))}
        </nav>
      </ViewTransition>
    </div>
  );
}

interface NavItemData {
  href: string;
  label: string;
  isExternal?: boolean;
}

interface NavItemProps {
  href: string;
  label: string;
  children: React.ReactNode;
  isExternal?: boolean;
}

function NavItem(props: NavItemProps) {
  const pathname = usePathname();
  const isActive =
    !props.isExternal &&
    (props.href === '/' ? pathname === '/' : pathname === props.href || pathname.startsWith(props.href + '/'));

  const [isDevHovered, setIsDevHovered] = React.useState(false);

  const linkClassName = `px-4 py-2 rounded-full transition shadow-sm flex items-center gap-1 ${
    isActive
      ? 'bg-neutral-200 dark:bg-neutral-800 text-black dark:text-white font-bold'
      : 'bg-neutral-100 dark:bg-neutral-900 text-black dark:text-white hover:bg-neutral-300 dark:hover:bg-neutral-800'
  }`;

  if (props.label === 'Dev') {
    return (
      <div className="relative" onMouseEnter={() => setIsDevHovered(true)} onMouseLeave={() => setIsDevHovered(false)}>
        <a href={props.href} target="_blank" rel="noopener noreferrer" className={linkClassName}>
          {props.children}
          <ExternalLinkIcon />
        </a>
        {isDevHovered && <DevHoverCard />}
      </div>
    );
  }

  return (
    <Link href={props.href} className={linkClassName}>
      {props.children}
    </Link>
  );
}

interface AnimatedChar {
  char: string;
  transition?: string;
  spaceAfter?: boolean;
  currentClass?: string;
  className?: string;
  key?: string | number; // For react list keys if needed later
}

interface AnimationStep {
  id: number;
  text: AnimatedChar[];
  bold?: boolean;
  blink?: boolean;
}

const animationSteps: AnimationStep[] = [
  {
    id: 0,
    text: [
      { char: 'N' },
      { char: 'u' },
      { char: 'r' },
      { char: 'u' },
      { char: 'l' },
      { char: ' ' },
      { char: 'H' },
      { char: 'u' },
      { char: 'd' },
      { char: 'a' },
    ],
  },
  {
    id: 1,
    text: [
      { char: 'n', transition: 'opacity-0' },
      { char: 'u' },
      { char: 'r' },
      { char: 'u' },
      { char: 'l' },
      { char: ' ' },
      { char: 'h', transition: 'opacity-0' },
      { char: 'u' },
      { char: 'd' },
      { char: 'a' },
    ],
  },
  {
    id: 2,
    text: [
      { char: 'n' },
      { char: 'u' },
      { char: 'r', transition: 'opacity-0 scale-0', spaceAfter: true },
      { char: 'u', transition: 'opacity-0 scale-0' },
      { char: 'l', transition: 'opacity-0 scale-0' },
      { char: ' ' },
      { char: 'h' },
      { char: 'u' },
      { char: 'd' },
      { char: 'a' },
    ],
  },
  {
    id: 3,
    text: [
      { char: 'n' },
      { char: 'u' },
      { char: ' ' },
      { char: 'h' },
      { char: 'u' },
      { char: 'd', transition: 'opacity-0 scale-0', spaceAfter: true },
      { char: 'a', transition: 'opacity-0 scale-0' },
    ],
  },
  {
    id: 4,
    text: [
      { char: 'n', transition: 'translate-x-0' },
      { char: 'u', transition: 'translate-x-0' },
      { char: 'h', transition: 'translate-x-0' },
      { char: 'u', transition: 'translate-x-0' },
    ],
  },
  {
    id: 5,
    text: [
      { char: 'n' },
      { char: 'u' },
      { char: 'h' },
      { char: 'u' },
      { char: '.', transition: 'opacity-0' },
      { char: 'd', transition: 'opacity-0' },
      { char: 'e', transition: 'opacity-0' },
      { char: 'v', transition: 'opacity-0' },
    ],
  },
  {
    id: 6,
    text: [
      { char: 'n' },
      { char: 'u' },
      { char: 'h' },
      { char: 'u' },
      { char: '.' },
      { char: 'd' },
      { char: 'e' },
      { char: 'v' },
    ],
    bold: true,
    blink: true,
  },
];

const DURATION_NORMAL = 150;
const DURATION_TRANSFORM = 300;
const DURATION_TYPEWRITER_CHAR = 100;
const DURATION_REMOVAL = 200;
const DURATION_JOIN = 300;
const DURATION_FINAL_BLINK_INTERVAL = 500;

function DevHoverCard() {
  const [currentStep, setCurrentStep] = React.useState(0);
  const [displayedText, setDisplayedText] = React.useState<AnimatedChar[]>(
    animationSteps[0].text.map((c, i) => ({ ...c, key: `char-${0}-${i}` })),
  );
  const [typewriterIndex, setTypewriterIndex] = React.useState(0);
  const [isBlinking, setIsBlinking] = React.useState(false);

  React.useEffect(() => {
    const stepData = animationSteps[currentStep];
    let timeoutId: NodeJS.Timeout;

    if (currentStep === 0) {
      // Nurul Huda
      setDisplayedText(
        stepData.text.map((t, i) => ({ ...t, currentClass: 'opacity-100', key: `char-${currentStep}-${i}` })),
      );
      timeoutId = setTimeout(() => setCurrentStep(1), DURATION_TRANSFORM * 3);
    } else if (currentStep === 1) {
      // nurul huda (N->n, H->h)
      const initialChars: AnimatedChar[] = [
        { char: 'n', currentClass: 'opacity-0' },
        { char: 'u' },
        { char: 'r' },
        { char: 'u' },
        { char: 'l' },
        { char: ' ' },
        { char: 'h', currentClass: 'opacity-0' },
        { char: 'u' },
        { char: 'd' },
        { char: 'a' },
      ];
      setDisplayedText(initialChars.map((t, i) => ({ ...t, key: `char-${currentStep}-initial-${i}` })));
      setTimeout(() => {
        const transitionedChars: AnimatedChar[] = [
          { char: 'n', currentClass: 'opacity-100 transition-opacity duration-300' },
          { char: 'u' },
          { char: 'r' },
          { char: 'u' },
          { char: 'l' },
          { char: ' ' },
          { char: 'h', currentClass: 'opacity-100 transition-opacity duration-300' },
          { char: 'u' },
          { char: 'd' },
          { char: 'a' },
        ];
        setDisplayedText(transitionedChars.map((t, i) => ({ ...t, key: `char-${currentStep}-final-${i}` })));
      }, 50);
      timeoutId = setTimeout(() => setCurrentStep(2), DURATION_TRANSFORM * 3);
    } else if (currentStep === 2) {
      // nu huda (rul fades out)
      const initialChars: AnimatedChar[] = [
        { char: 'n' },
        { char: 'u' },
        { char: 'r', currentClass: 'opacity-100 transition-all duration-200' },
        { char: 'u', currentClass: 'opacity-100 transition-all duration-200' },
        { char: 'l', currentClass: 'opacity-100 transition-all duration-200' },
        { char: ' ', currentClass: 'transition-all duration-200' },
        { char: 'h' },
        { char: 'u' },
        { char: 'd' },
        { char: 'a' },
      ];
      setDisplayedText(initialChars.map((t, i) => ({ ...t, key: `char-${currentStep}-initial-${i}` })));
      setTimeout(() => {
        const finalChars: AnimatedChar[] = [
          { char: 'n' },
          { char: 'u', className: 'mr-[-0.25em] transition-all duration-300' },
          { char: 'r', currentClass: 'opacity-0 scale-50 w-0' },
          { char: 'u', currentClass: 'opacity-0 scale-50 w-0' },
          { char: 'l', currentClass: 'opacity-0 scale-50 w-0' },
          { char: ' ', currentClass: 'opacity-0 w-0' },
          { char: 'h' },
          { char: 'u' },
          { char: 'd' },
          { char: 'a' },
        ];
        setDisplayedText(finalChars.map((t, i) => ({ ...t, key: `char-${currentStep}-final-${i}` })));
      }, 50);
      timeoutId = setTimeout(() => setCurrentStep(3), DURATION_REMOVAL * 3);
    } else if (currentStep === 3) {
      // nu hu (da fades out)
      const initialChars: AnimatedChar[] = [
        { char: 'n' },
        { char: 'u' },
        { char: ' ' },
        { char: 'h' },
        { char: 'u' },
        { char: 'd', currentClass: 'opacity-100 transition-all duration-200' },
        { char: 'a', currentClass: 'opacity-100 transition-all duration-200' },
      ];
      setDisplayedText(initialChars.map((t, i) => ({ ...t, key: `char-${currentStep}-initial-${i}` })));
      setTimeout(() => {
        const finalChars: AnimatedChar[] = [
          { char: 'n' },
          { char: 'u' },
          { char: ' ', className: 'mr-[-0.25em] transition-all duration-300' },
          { char: 'h' },
          { char: 'u' },
          { char: 'd', currentClass: 'opacity-0 scale-50 w-0' },
          { char: 'a', currentClass: 'opacity-0 scale-50 w-0' },
        ];
        setDisplayedText(finalChars.map((t, i) => ({ ...t, key: `char-${currentStep}-final-${i}` })));
      }, 50);
      timeoutId = setTimeout(() => setCurrentStep(4), DURATION_REMOVAL * 3);
    } else if (currentStep === 4) {
      // nuhu (join)
      const initialChars: AnimatedChar[] = [
        { char: 'n', currentClass: 'inline-block transition-transform duration-300 translate-x-[-2px]' },
        { char: 'u', currentClass: 'inline-block transition-transform duration-300 translate-x-[-2px]' },
        { char: 'h', currentClass: 'inline-block transition-transform duration-300 translate-x-[2px]' },
        { char: 'u', currentClass: 'inline-block transition-transform duration-300 translate-x-[2px]' },
      ];
      setDisplayedText(initialChars.map((t, i) => ({ ...t, key: `char-${currentStep}-initial-${i}` })));
      setTimeout(() => {
        const finalChars: AnimatedChar[] = [
          { char: 'n', currentClass: 'inline-block transition-transform duration-300 translate-x-0' },
          { char: 'u', currentClass: 'inline-block transition-transform duration-300 translate-x-0' },
          { char: 'h', currentClass: 'inline-block transition-transform duration-300 translate-x-0' },
          { char: 'u', currentClass: 'inline-block transition-transform duration-300 translate-x-0' },
        ];
        setDisplayedText(finalChars.map((t, i) => ({ ...t, key: `char-${currentStep}-final-${i}` })));
      }, 50);
      timeoutId = setTimeout(() => {
        setCurrentStep(5);
        setTypewriterIndex(0);
      }, DURATION_JOIN * 2);
    } else if (currentStep === 5) {
      // nuhu.dev (typewriter)
      const baseText: AnimatedChar[] = [{ char: 'n' }, { char: 'u' }, { char: 'h' }, { char: 'u' }];
      const toType: AnimatedChar[] = [{ char: '.' }, { char: 'd' }, { char: 'e' }, { char: 'v' }];

      if (typewriterIndex < toType.length) {
        const currentTyped = toType.slice(0, typewriterIndex + 1).map((c, i) => ({
          ...c,
          currentClass: 'opacity-100 transition-opacity duration-100',
          key: `typewriter-${i}`,
        }));
        setDisplayedText([...baseText.map((c, i) => ({ ...c, key: `base-${i}` })), ...currentTyped]);
        timeoutId = setTimeout(() => setTypewriterIndex((prev) => prev + 1), DURATION_TYPEWRITER_CHAR);
      } else {
        timeoutId = setTimeout(() => setCurrentStep(6), DURATION_TYPEWRITER_CHAR * 3);
      }
    } else if (currentStep === 6) {
      // nuhu.dev (bold, blink)
      const finalText: AnimatedChar[] = [
        { char: 'n' },
        { char: 'u' },
        { char: 'h' },
        { char: 'u' },
        { char: '.' },
        { char: 'd' },
        { char: 'e' },
        { char: 'v' },
      ];
      setDisplayedText(finalText.map((c, i) => ({ ...c, currentClass: 'font-bold', key: `final-${i}` })));
      const blinkInterval = setInterval(() => {
        setIsBlinking((prev) => !prev);
      }, DURATION_FINAL_BLINK_INTERVAL);
      return () => clearInterval(blinkInterval); // Cleanup interval on unmount or step change
    }

    return () => clearTimeout(timeoutId);
  }, [currentStep, typewriterIndex]);

  // Reset animation when component might be re-hovered after unmounting
  React.useEffect(() => {
    return () => {
      setCurrentStep(0);
      setTypewriterIndex(0);
      setIsBlinking(false);
    };
  }, []);

  return (
    <div className="absolute top-full mt-2 left-1/2 -translate-x-1/2 p-6 bg-white dark:bg-neutral-900 rounded-lg shadow-xl z-10 w-auto min-w-[180px] flex justify-center items-center">
      <div
        className={`text-2xl text-black dark:text-white transition-all duration-300 flex flex-nowrap ${animationSteps[currentStep]?.bold ? 'font-bold' : ''} ${isBlinking ? 'animate-pulse' : ''}`}
      >
        {displayedText.map((item, index) => (
          <span key={item.key || index} className={`whitespace-pre ${item.currentClass || ''} ${item.className || ''}`}>
            {item.char}
          </span>
        ))}
      </div>
    </div>
  );
}

const ExternalLinkIcon = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width="24"
    height="24"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className="w-4 h-4 lucide lucide-external-link-icon lucide-external-link"
  >
    <path d="M15 3h6v6" />
    <path d="M10 14 21 3" />

    <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" />
  </svg>
);
