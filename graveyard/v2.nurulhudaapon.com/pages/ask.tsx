import Ask, { Questions } from 'components/Ask';
import Container from 'components/Container';
import Subscribe from 'components/Subscribe';
import { useState } from 'react';

export default function Newsletter() {
    const [time, setTime] = useState(new Date());
    return (
        <Container title="Ask – Nurul Huda (Apon)" description="Anonymously ask me anything" image={'https://nurulhudaapon.com/static/images/ask-banner.png'}>
            <div className="mx-auto mb-16 flex max-w-2xl flex-col items-start justify-center">
                <h1 className="mb-4 text-3xl font-bold tracking-tight text-black dark:text-white md:text-5xl">Ask Me Anything</h1>
                <p className="mb-4 text-gray-600 dark:text-gray-400">
                    Anonymously ask me anything. I'll answer it in my social media or you can find the answer by revisiting this page.
                </p>
                <Ask added={() => setTime(new Date())} selected={null} />
                <Questions time={time} />
            </div>
        </Container>
    );
}
