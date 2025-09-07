import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // output: 'export', // Commented out to enable API routes
  experimental: {
    viewTransition: true,
  },
};

export default nextConfig;
