import cn from 'classnames';
import Link from 'next/link';
import { useState, useEffect } from 'react';
import styles from 'styles/mobile-menu.module.css';
import { MENU_ITEMS } from './Resources';

export default function MobileMenu() {
    const [isMenuOpen, setIsMenuOpen] = useState(false);

    function toggleMenu() {
        if (isMenuOpen) {
            setIsMenuOpen(false);
            document.body.style.overflow = '';
        } else {
            setIsMenuOpen(true);
            document.body.style.overflow = 'hidden';
        }
    }

    useEffect(() => {
        return function cleanup() {
            document.body.style.overflow = '';
        };
    }, []);

    return (
        <>
            <button className={cn(styles.burger, 'visible md:hidden')} aria-label="Toggle menu" type="button" onClick={toggleMenu}>
                <MenuIcon data-hide={isMenuOpen} />
                <CrossIcon data-hide={!isMenuOpen} />
            </button>
            {isMenuOpen && (
                <ul className={cn(styles.menu, 'absolute flex flex-col bg-gray-100 transition delay-150 ease-in-out  dark:bg-gray-900', styles.menuRendered)}>
                    {MENU_ITEMS.map(({ href, text }) => (
                        <li
                            className="border-b border-gray-300 text-sm font-semibold text-gray-900 dark:border-gray-700 dark:text-gray-100"
                            style={{ transitionDelay: '150ms', transitionDuration: '150ms', transitionProperty: 'all', transitionTimingFunction: 'ease-in-out' }}
                            key={href}
                        >
                            <Link className="flex w-auto pb-4" href={href} target={href.startsWith('http') ? '_blank' : '_self'}>
                                {text}
                            </Link>
                        </li>
                    ))}
                </ul>
            )}
        </>
    );
}

function MenuIcon(props: JSX.IntrinsicElements['svg']) {
    return (
        <svg className="absolute h-5 w-5 text-gray-900 dark:text-gray-100" width="20" height="20" viewBox="0 0 20 20" fill="none" {...props}>
            <path d="M2.5 7.5H17.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            <path d="M2.5 12.5H17.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
    );
}

function CrossIcon(props: JSX.IntrinsicElements['svg']) {
    return (
        <svg
            className="absolute h-5 w-5 text-gray-900 dark:text-gray-100"
            viewBox="0 0 24 24"
            width="24"
            height="24"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
            shapeRendering="geometricPrecision"
            {...props}
        >
            <path d="M18 6L6 18" />
            <path d="M6 6l12 12" />
        </svg>
    );
}
