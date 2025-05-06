import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { Github, Linkedin, Twitter, Mail, Package, Youtube } from "lucide-react";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Nurul Huda (Apon)",
  description: "A tech enthusiast, enrolling in Computer Science and Engineering at Green University of Bangladesh and working as a Staff Engineer",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        <div className="grid grid-rows-[1fr_auto] min-h-screen bg-neutral-950 text-white font-sans">
          {children}
          <footer className="w-full flex flex-row items-center justify-between gap-4 py-6 border-t border-neutral-800 bg-neutral-950 px-4 sm:px-8 text-sm">
            <div className="text-neutral-500">© 2025 Nurul Huda (Apon).</div>
            <div className="flex gap-4 sm:gap-5 items-center">
              <a href="https://github.com/nurulhudaapon" target="_blank" rel="noopener noreferrer" aria-label="GitHub" className="text-neutral-400 hover:text-white transition"><Github className="w-4 h-4" /></a>
              <a href="https://linkedin.com/in/nurulhudaapon" target="_blank" rel="noopener noreferrer" aria-label="LinkedIn" className="text-neutral-400 hover:text-white transition"><Linkedin className="w-4 h-4" /></a>
              <a href="https://twitter.com/nurulhudaapon" target="_blank" rel="noopener noreferrer" aria-label="Twitter" className="text-neutral-400 hover:text-white transition"><Twitter className="w-4 h-4" /></a>
              <a href="mailto:me@nurulhudaapon.com" aria-label="Email" className="text-neutral-400 hover:text-white transition"><Mail className="w-4 h-4" /></a>
              <a href="https://www.npmjs.com/~nurulhudaapon" target="_blank" rel="noopener noreferrer" aria-label="npm" className="text-neutral-400 hover:text-white transition"><Package className="w-4 h-4" /></a>
              <a href="https://youtube.com/@nurulhudaapon" target="_blank" rel="noopener noreferrer" aria-label="YouTube" className="text-neutral-400 hover:text-white transition"><Youtube className="w-4 h-4" /></a>
            </div>
          </footer>
        </div>
      </body>
    </html>
  );
}
