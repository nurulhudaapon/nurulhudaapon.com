import Link from 'next/link';
import Image from 'next/image';

import Container from 'components/Container';
import avatar from 'public/avatar.jpg';

export default function About() {
  return (
    <Container title="About – Nurul Huda (Apon)">
      <div className="flex flex-col justify-center items-start max-w-2xl mx-auto mb-16 w-full">
        <h1 className="font-bold text-3xl md:text-5xl tracking-tight mb-4 text-black dark:text-white">
          About Me
        </h1>
        <div className="mb-8 prose dark:prose-dark leading-6">
          <h2>Find me on the web</h2>
          <ul>
            <li>
              Twitter: <a href="https://twitter.com/nurulhudaapon">@nurulhudaapon</a>
            </li>
            <li>
              GitHub: <a href="https://github.com/nurulhudaapon">@nurulhudaapon</a>
            </li>
            <li>
              Website:{' '}
              <Link href="https://nurulhudaapon.com">
                https://nurulhudaapon.com
              </Link>
            </li>
            <li>
              LinkedIn:{' '}
              <a href="https://www.linkedin.com/in/nurulhudaapon/">
                https://www.linkedin.com/in/nurulhudaapon
              </a>
            </li>
          </ul>
          <h2>Bio</h2>
          <p>
            Hello, I'm Nurul. I'm a Software Engineer at{' '}
            <a href="https://voyagesms.com/">Voyage SMS</a>, where I build stuff using C#, .NET Core, React, TypeScript, PostgreSQL and many more. I'm also a Computer Science and Engineering student at Green University of Bangladesh.
          </p>
          <h3>Current Position</h3>
          <p>Nurul Huda (Apon), Software Engineer at Voyage SMS</p>
          <h3>Education</h3>
          <p>
            Currently enrolling Bachelor of Computer Science and Engineering at Greeen University of Bangladesh and expected to graducate in 2026.
          </p>
          <h2>Here is me</h2>
          <div className="flex space-x-8">
            <a href="/avatar.jpg">
              <Image
                alt="Nurul Huda (Apon) headshot"
                width={400}
                quality={100}
                src={avatar}
                className={`rounded-md filter dark:grayscale`}
              />
            </a>
            
          </div>
        </div>
      </div>
    </Container>
  );
}
