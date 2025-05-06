'use client';

import Link from 'next/link';

const navItems = [
  { href: '/', label: 'Home' },
  { href: '/blog', label: 'Blog' },
  { href: '/about', label: 'About' },
];

export default function Navigation() {
  return (
    <nav className="flex gap-4 sm:gap-6 text-base sm:text-lg font-medium">
      {navItems.map((item) => (
        <NavItem key={item.href} href={item.href}>
          {item.label}
        </NavItem>
      ))}
    </nav>
  );
}

function NavItem(props: { href: string; children: React.ReactNode }) {
  return (
    <Link 
      href={props.href} 
      className="px-4 py-2 rounded-full bg-neutral-900 hover:bg-neutral-800 active:bg-neutral-800 active:text-white active:font-bold transition shadow-sm"
    >
      {props.children}
    </Link>
  );
}