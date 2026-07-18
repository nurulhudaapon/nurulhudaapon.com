import { Questions } from './component';
import { Ask } from './form';
import { getQuestionsForVisitor } from './data';
import { Cmd } from '@/components/cmd';
import { cookies } from 'next/headers';

interface AskPageProps {
  searchParams: Promise<{
    admin: string | undefined;
    success: string | undefined;
    q_id: string | undefined;
    mode: string | undefined;
  }>;
}

export default async function AskPage(props: AskPageProps) {
  const params = await props.searchParams;
  const { admin, q_id, mode } = params;
  const adminParam = admin;
  const questionId = q_id;
  const isAdmin = !!adminParam;
  const isAnswering = isAdmin && questionId;
  const cookieStore = await cookies();
  const visitorId = cookieStore.get('visitor_id')?.value;

  // Fetch questions server-side
  const questions = await getQuestionsForVisitor(adminParam);

  // Find the question being answered
  const questionToAnswer = isAnswering ? questions.find((q) => q._id === questionId) : null;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-semibold text-black dark:text-white mb-4">Ask Me Anything</h1>
        <p className="text-neutral-600 dark:text-neutral-300">
          Anonymously ask me anything. I'll answer it in my social media or you can find the answer by revisiting this
          page.
        </p>
      </div>

      <Ask
        key={questionId}
        isAdmin={isAdmin}
        questionId={questionId}
        adminCredential={adminParam}
        existingAnswer={questionToAnswer?.answer}
        questionText={questionToAnswer?.question}
      />

      <Questions
        time={new Date()}
        questions={questions}
        isAdmin={isAdmin}
        mode={mode}
        adminCredential={adminParam}
        visitorId={visitorId}
      />
      <Cmd
        params={{ mode: mode === 'screenshots' ? 'answer' : 'screenshots' }}
        cmd={{ key: '.', altKey: false, ctrlKey: true, metaKey: false, shiftKey: false }}
      />
    </div>
  );
}
