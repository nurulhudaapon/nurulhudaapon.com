import type { Metadata } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import { FooterLink } from './components/footer-link';
import { GoogleTagManager } from '@next/third-parties/google';

import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

const ogImage = '/social.webp';
export const metadata: Metadata = {
  title: 'Nurul Huda (Apon)',
  description:
    'A tech enthusiast, enrolling in Computer Science and Engineering at Green University of Bangladesh and working as a Staff Engineer',
  metadataBase: new URL('https://next.nuhu.dev'),
  openGraph: {
    title: 'Nurul Huda (Apon)',
    description:
      'A tech enthusiast, enrolling in Computer Science and Engineering at Green University of Bangladesh and working as a Staff Engineer',
    type: 'website',
    images: [ogImage],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Nurul Huda (Apon)',
    description:
      'A tech enthusiast, enrolling in Computer Science and Engineering at Green University of Bangladesh and working as a Staff Engineer',
    images: [ogImage],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="[color-scheme:light_dark]">
      <GoogleTagManager gtmId="GTM-K4HPMTZ4" />

      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased dark:bg-neutral-950 dark:text-white bg-white text-black font-sans`}
      >
        <div className="grid grid-rows-[1fr_auto] min-h-screen dark:bg-neutral-950 bg-white dark:text-white text-black font-sans">
          {children}
          <footer className="sticky z-55 sm:static bottom-0 w-full flex flex-row items-center justify-between gap-4 py-3 sm:py-6 border-t dark:border-neutral-800 border-neutral-200 dark:bg-neutral-950 bg-white px-4 sm:px-8 text-sm">
            <div className="dark:text-neutral-400 text-neutral-600 text-xs sm:text-sm line-clamp-1">
              © 2025 Nurul Huda (Apon).
            </div>
            <div className="flex gap-3 sm:gap-4 items-center">
              {socialLinks.map((link) => (
                <FooterLink key={link.label} {...link} />
              ))}
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}

const NpmIcon = () => (
  <svg fill="currentColor" className="w-4 sm:w-5" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <title>npm</title>
    <path d="M1.763 0C.786 0 0 .786 0 1.763v20.474C0 23.214.786 24 1.763 24h20.474c.977 0 1.763-.786 1.763-1.763V1.763C24 .786 23.214 0 22.237 0zM5.13 5.323l13.837.019-.009 13.836h-3.464l.01-10.382h-3.456L12.04 19.17H5.113z" />
  </svg>
);

const GitHubIcon = () => (
  <svg fill="currentColor" className="w-4 sm:w-5" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <title>GitHub</title>
    <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
  </svg>
);

const XIcon = () => (
  <svg fill="currentColor" className="w-4 sm:w-5" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <title>X</title>
    <path d="M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z" />
  </svg>
);

const YouTubeIcon = () => (
  <svg fill="currentColor" className="w-4 sm:w-5" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <title>YouTube</title>
    <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" />
  </svg>
);

const EmailIcon = () => (
  <svg
    className="w-4 sm:w-5"
    xmlns="http://www.w3.org/2000/svg"
    width="24"
    height="24"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
  >
    <path d="m22 7-8.991 5.727a2 2 0 0 1-2.009 0L2 7" />
    <rect x="2" y="4" width="20" height="16" rx="2" />
  </svg>
);

const LinkedInIcon = () => (
  <svg fill="currentColor" className="w-4 sm:w-5" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <title>LinkedIn</title>
    <path d="M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-2-2 2 2 0 0 0-2 2v7h-4v-7a6 6 0 0 1 6-6z" />
    <rect width="4" height="12" x="2" y="9" />
    <circle cx="4" cy="4" r="2" />
  </svg>
);

const socialLinks = [
  { icon: <EmailIcon />, href: 'mailto:me@nurulhudaapon.com', label: 'Email' },
  { icon: <GitHubIcon />, href: 'https://github.com/nurulhudaapon', label: 'GitHub' },
  { icon: <NpmIcon />, href: 'https://www.npmjs.com/~nurulhudaapon', label: 'NPM' },
  { icon: <XIcon />, href: 'https://x.com/nurulhudaapon', label: 'X' },
  { icon: <LinkedInIcon />, href: 'https://linkedin.com/in/nurulhudaapon', label: 'LinkedIn' },
  { icon: <YouTubeIcon />, href: 'https://youtube.com/@nurulhudaapon', label: 'YouTube' },
];
