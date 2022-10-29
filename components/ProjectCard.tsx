import Link from 'next/link';
import cn from 'classnames';
import 'devicon/devicon.min.css';

export default function ProjectCard({
  title,
  repoUrl,
  description,
  languages = []
}) {
  return (
    <Link
      href={`${repoUrl}`}
      target="_blank"
      className={cn(
        'transform hover:scale-[1.01] transition-all',
        'rounded-xl w-full md:w-1/3 bg-gradient-to-r p-1',
        'border border-gray-400 dark:border-white'
      )}
    >
      <div className="flex place-content-between flex-col h-full bg-white dark:bg-gray-900 rounded-lg p-4">
        <div className="flex flex-col md:flex-row justify-between">
          <h4 className="text-md md:text-md font-medium mb-6 sm:mb-10 w-full text-gray-900 dark:text-gray-100 tracking-tight">
            {title}
          </h4>
        </div>

        <p className="text-gray-600 dark:text-gray-400">{description}</p>

        <div>
          <span className="ml-1 mt-4 align-baseline capsize">
            {languages.map((lang) => (
              <span
                key={lang}
                style={{ fontSize: 25 }}
                className={`devicon-${lang}-plain colored mr-2`}
              ></span>
            ))}
          </span>
        </div>
      </div>
    </Link>
  );
}
