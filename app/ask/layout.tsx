import { MainLayout } from '@/components/layout';
import { Metadata } from 'next';

const ogImage = '/ask.png';
const description =
  'Anonymously ask Nurul Huda (Apon) anything. Answers will be provided via social media or you can find the answer by revisiting the ask page.';
const title = 'NH | Ask';

export const metadata: Metadata = {
  title,
  description,
  metadataBase: new URL(process.env.NEXT_PUBLIC_BASE_URL),
  openGraph: {
    title,
    description,
    type: 'website',
    images: [ogImage],
  },
  twitter: {
    card: 'summary_large_image',
    title,
    description,
    images: [ogImage],
  },
};

export default MainLayout;
