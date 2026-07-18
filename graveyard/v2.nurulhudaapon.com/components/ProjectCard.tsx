import Link from 'next/link';
import cn from 'classnames';
import 'devicon/devicon.min.css';
import Image from 'next/image';

export default function ProjectCard({ title, repoUrl, description, languages = [] }) {
    return (
        <Link
            href={`${repoUrl}`}
            target="_blank"
            className={cn('transform transition-all hover:scale-[1.01]', 'w-full rounded-xl bg-gradient-to-r p-1 md:w-1/3', 'border border-gray-400 dark:border-white')}
        >
            <div className="flex h-full flex-col place-content-between rounded-lg bg-white p-4 dark:bg-gray-900">
                <div className="flex flex-col justify-between md:flex-row">
                    <h4 className="text-md md:text-md mb-6 w-full font-medium tracking-tight text-gray-900 dark:text-gray-100 sm:mb-10">{title}</h4>
                </div>

                <p className="text-gray-600 dark:text-gray-400">{description}</p>

                <div>
                    <span className="capsize ml-1 mt-4 align-baseline">
                        {/* {languages.map((lang) => (
                            <Image
                                alt={lang}
                                key={lang}
                                className="colored mr-2"
                                src={`https://cdn.jsdelivr.net/gh/devicons/devicon/icons/${lang}/${lang}-original.svg`}
                                width={25}
                                height={25}
                            />
                        ))} */}

                        {languages.map((lang) => (
                            <span key={lang} style={{ fontSize: 25 }} className={`devicon-${lang}-plain colored mr-2`}></span>
                        ))}
                    </span>
                </div>
            </div>
        </Link>
    );
}
