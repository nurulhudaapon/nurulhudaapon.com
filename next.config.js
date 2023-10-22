/**
 * @type {import('next').NextConfig}
 */
module.exports = {
    reactStrictMode: true,
    images: {
        domains: [
            'pbs.twimg.com', // Twitter Profile Picture
            'res.cloudinary.com',
            'cdn.jsdelivr.net',
        ],
    },
    // redirect old blog posts to medium
    async redirects() {
        // https://nurulhudaapon.medium.com/tips-on-staying-focused-53e42eed981c
        // https://nurulhudaapon.medium.com/how-i-study-while-working-full-time-e8c6a511cb4a
        // https://nurulhudaapon.medium.com/learn-to-type-fast-2301e4ce0a2

        return [
            {
                // https://nurulhudaapon.com/blog/stay-focused?fbclid=IwAR1UxcE1jKdIsiIO0lfYAuRv5XL4hR3cGdHK7XsaJv0BJdBQxcAC6fiY-g0
                source: '/blog/stay-focused',
                destination: 'https://nurulhudaapon.medium.com/tips-on-staying-focused-53e42eed981c',
                permanent: true,
            },
            {
                // https://nurulhudaapon.com/blog/study-while-working-full-time?fbclid=IwAR3mX2js2CdumrzBtUMZUInn08nj0bbzs_htCEuGSZ-5IGdwhZnGaeXMKiw
                source: '/blog/study-while-working-full-time',
                destination: 'https://nurulhudaapon.medium.com/how-i-study-while-working-full-time-e8c6a511cb4a',
                permanent: true,
            },
            {
                // https://nurulhudaapon.com/blog/learn-typing-fast?fbclid=IwAR1IrzViB_jfCHNBvD6--D1NNtRDx6wIBZu4tAwtBxQ_cwsLYKc7QOear0A
                source: '/blog/learn-typing-fast',
                destination: 'https://nurulhudaapon.medium.com/learn-to-type-fast-2301e4ce0a2',
                permanent: true,
            },
        ];
    },

    webpack: (config) => {
        config.module.rules.push({
            test: /\.(graphql|gql)$/,
            exclude: /node_modules/,
            loader: 'graphql-tag/loader',
        });
        return config;
    },
    experimental: {
        legacyBrowsers: false,
    },
    async headers() {
        return [
            {
                source: '/(.*)',
                headers: securityHeaders,
            },
        ];
    },
};

// https://nextjs.org/docs/advanced-features/security-headers
const ContentSecurityPolicy = `
    default-src 'self';
    script-src 'self' 'unsafe-eval' 'unsafe-inline' *.youtube.com *.twitter.com *.google.com *.google-analytics.com *.googletagmanager.com *.googleapis.com;
    child-src *.youtube.com *.google.com *.twitter.com;
    style-src 'self' 'unsafe-inline' *.googleapis.com *.google.com *.google-analytics.com *.googletagmanager.com *.twitter.com *.youtube.com;
    img-src * blob: data:;
    media-src 'none';
    connect-src *;
    font-src 'self';
`;

const securityHeaders = [
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
    {
        key: 'Content-Security-Policy',
        value: ContentSecurityPolicy.replace(/\n/g, ''),
    },
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referrer-Policy
    {
        key: 'Referrer-Policy',
        value: 'origin-when-cross-origin',
    },
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options
    {
        key: 'X-Frame-Options',
        value: 'DENY',
    },
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Content-Type-Options
    {
        key: 'X-Content-Type-Options',
        value: 'nosniff',
    },
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-DNS-Prefetch-Control
    {
        key: 'X-DNS-Prefetch-Control',
        value: 'on',
    },
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security
    {
        key: 'Strict-Transport-Security',
        value: 'max-age=31536000; includeSubDomains; preload',
    },
    // https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Feature-Policy
    {
        key: 'Permissions-Policy',
        value: 'camera=(), microphone=(), geolocation=()',
    },
];
