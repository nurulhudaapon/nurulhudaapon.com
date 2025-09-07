import { handleQuestionSubmit, handleDeleteQuestion } from './action';
import Link from 'next/link';

export function AdminQuestions({
  questions,
  isAdmin,
  adminCredential,
  mode,
}: {
  questions: Question[];
  isAdmin: boolean;
  adminCredential?: string;
  mode?: string;
}) {
  if (!questions?.length) return null;

  const isScreenshots = mode === 'screenshots';

  return (
    <div className="mt-4 flex w-full flex-col gap-2">
      <h4 className="font-semibold text-gray-600 dark:text-white">{isAdmin ? 'All Questions' : 'Your questions'}</h4>
      {questions.map((question) => (
        <div key={question._id} className="flex flex-row">
          <div className="border-2 "></div>
          <div className="border-gray-200 w-full rounded border p-3 dark:border-gray-800 dark:bg-blue-opaque">
            <div className="question gap-1">
              {!isAdmin && (
                <div className="mb-1 flex gap-2 items-center justify-between">
                  <div className="flex gap-2">
                    {isAdmin && (
                      <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
                        {question.visitorId ? `Visitor: ${question.visitorId}` : 'No Visitor ID'}
                      </span>
                    )}
                    {question.answer && (
                      <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                        Answered
                      </span>
                    )}
                  </div>
                  {isAdmin && (
                    <Link
                      href={`/ask?admin=${adminCredential}&q_id=${question._id}`}
                      className="inline-flex items-center px-2 py-1 text-xs font-medium text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 transition-colors"
                    >
                      {question.answer ? 'Update Answer' : 'Answer'}
                    </Link>
                  )}
                </div>
              )}

              <p className="question-text text-sm text-black dark:text-white">{question.question}</p>
              {question.answer && (
                <div className="mt-2 p-2 bg-gray-50 dark:bg-gray-800 rounded">
                  <p className="text-xs text-gray-600 dark:text-gray-400 mb-1">Answer:</p>
                  <p className="question-answer text-sm text-gray-800 dark:text-gray-200">{question.answer}</p>
                </div>
              )}

              {!isScreenshots && isAdmin && (
                <div className="mt-2 space-y-2">
                  {/* Visitor Details */}
                  {question.visitor && (
                    <div className="p-2 bg-blue-50 dark:bg-blue-900/20 rounded text-xs">
                      <p className="font-medium text-gray-700 dark:text-gray-300 mb-1">Visitor Details:</p>
                      <div className="space-y-1 text-gray-600 dark:text-gray-400">
                        {Object.entries(question.visitor).map(([key, value]) => (
                          <div key={key}>
                            <span className="font-medium">{toTitleCase(key)}:</span> {value}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Action Buttons */}
                  <div className="flex gap-2 items-center justify-end">
                    <Link
                      href={`/ask?admin=${adminCredential}&q_id=${question._id}`}
                      className="inline-flex items-center px-2 py-1 text-xs font-medium text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 transition-colors"
                    >
                      {question.answer ? 'Update Answer' : 'Answer'}
                    </Link>
                    <form action={handleDeleteQuestion} className="inline">
                      <input type="hidden" name="questionId" value={question._id} />
                      {adminCredential && <input type="hidden" name="adminCredential" value={adminCredential} />}
                      <button
                        type="submit"
                        className="inline-flex items-center px-2 py-1 text-xs font-medium text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 transition-colors"
                      >
                        Delete
                      </button>
                    </form>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

type Question = {
  _id: string;
  question: string;
  answer?: string;
  email?: string;
  createdAt: string;
  visitorId?: string;
  visitor?: {
    ip: string;
    userAgent: string;
    timestamp: string;
  };
};

type Props = {
  time: Date;
  questions: Question[];
  isAdmin?: boolean;
  adminCredential?: string;
  mode?: string;
};

export function Questions({ time, questions, isAdmin, adminCredential, mode }: Props) {
  if (!questions?.length) return null;

  // Use AdminQuestions component for admin mode (server component with links)
  if (isAdmin) {
    return <AdminQuestions mode={mode} questions={questions} isAdmin={isAdmin} adminCredential={adminCredential} />;
  }

  // Regular server component for non-admin mode
  return (
    <div className="mt-4 flex w-full flex-col gap-2">
      <h4 className="font-semibold text-gray-600 dark:text-white">Your questions</h4>
      {questions.map((question) => (
        <div key={question._id} className="flex flex-row">
          <div className="border-2 "></div>
          <div
            className="border-gray-200 w-full rounded border p-3 dark:border-gray-800 dark:bg-blue-opaque"
            key={question._id}
          >
            <div className="question gap-1">
              <div className="mb-1 flex gap-2">
                {question.answer && (
                  <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                    Answered
                  </span>
                )}
              </div>
              <p className="question-text text-sm text-black dark:text-white">{question.question}</p>
              {question.answer && (
                <div className="mt-2 p-2 bg-gray-50 dark:bg-gray-800 rounded">
                  <p className="text-xs text-gray-600 dark:text-gray-400 mb-1">Answer:</p>
                  <p className="question-answer text-sm text-gray-800 dark:text-gray-200">{question.answer}</p>
                </div>
              )}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

function toTitleCase(str: string) {
  return str.replace(/_/g, ' ').replace(/\b\w/g, (char) => char.toUpperCase());
}
