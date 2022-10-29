import BlogPostCard from "./BlogPostCard";
import ProjectCard from "./ProjectCard";

export const MENU_ITEMS = [
    {
        href: '/',
        text: 'Home'
    },
    {
        href: '/blog',
        text: 'Blog'
    },
    {
        href: '/snippets',
        text: 'Code Snippets'
    },
    {
        href: '/about',
        text: 'About'
    }
];

export const GLOBAL_CONFIG = {
    enableThemeSwitcher: false, // Change darkMode to class in Talewind config
    enableNewsletter: true,
    enableBlogSection: false,
    enableVideoSection: false,
}

const projects: Parameters<typeof ProjectCard>['0'][] = [
    {
        title: 'VS Code Extension',
        repoUrl: 'https://github.com/nurulhudaapon/enum-map-generator',
        description:
            'A VSCode extension for generating mapper from TS enum or JS enum like object',
        languages: ['typescript', 'vscode']
    },
    {
        title: 'Web API Template',
        repoUrl: 'https://github.com/nurulhudaapon/boilerplate-dotenet-mssql',
        description: '.Net Core Best Practices and Base Template for Web API',
        languages: ['csharp', 'dotnetcore', 'microsoftsqlserver']
    }
];

const posts: Parameters<typeof BlogPostCard>['0'][] = [
    {
        title: 'REST API Resources',
        slug: 'rest-api-resources',
        gradient: 'from-[#ff0080] to-[#7928CA]'
    },
    {
        title: 'REST API Resources',
        slug: 'coming-soon-0',
        gradient: 'from-[#ff0080] to-[#7928CA]'
    },
];

export const CONTENT = {
    projects,
    posts,
}
