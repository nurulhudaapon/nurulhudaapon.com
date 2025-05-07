'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { unstable_ViewTransition as ViewTransition } from 'react'

const navItems = [
  { href: '/', label: 'Home' },
  { href: '/blog', label: 'Blog' },
  { href: '/about', label: 'About' },
];

export default function Navigation() {
  return (
    <div className="sticky top-0 z-50 py-4 bg-white/80 dark:bg-neutral-950/80 backdrop-blur-sm w-full">
      <ViewTransition name="navigation">
        <nav className="flex gap-3 sm:gap-5 text-base sm:text-lg font-medium">
          {navItems.map((item) => (
            <NavItem key={item.href} href={item.href}>
              {item.label}
            </NavItem>
          ))}
        </nav>
      </ViewTransition>
    </div>
  );
}

function NavItem(props: { href: string; children: React.ReactNode }) {
  const pathname = usePathname();
  const isActive = props.href === '/' 
    ? pathname === '/' 
    : pathname === props.href || pathname.startsWith(props.href + '/');
  
  return (
    <Link 
      href={props.href} 
      className={`px-4 py-2 rounded-full transition shadow-sm ${
        isActive 
          ? 'bg-neutral-200 dark:bg-neutral-800 text-black dark:text-white font-bold' 
          : 'bg-neutral-100 dark:bg-neutral-900 text-black dark:text-white hover:bg-neutral-300 dark:hover:bg-neutral-800'
      }`}
    >
      {props.children}
    </Link>
  );
}