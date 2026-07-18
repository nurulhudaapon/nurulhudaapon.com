import { handleDeleteQuestion } from './action';
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
              {!isScreenshots && (
                <div className="mb-1 flex gap-2 items-center justify-between">
                  <div className="flex gap-2">
                    {question.answer && (
                      <span
                        className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                          question.seen
                            ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                            : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200'
                        }`}
                      >
                        {question.seen ? 'Answered & Seen' : 'Answered (Unseen)'}
                      </span>
                    )}
                  </div>
                </div>
              )}

              <div className="mb-2">
                <p className="question-text text-sm text-black dark:text-white">{question.question}</p>
                {!isScreenshots && (
                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    Asked on {formatDate(new Date(question.createdAt))} at{' '}
                    {new Date(question.createdAt).toLocaleTimeString()}
                  </p>
                )}
              </div>
              {question.answer && (
                <div className="mt-2 p-2 bg-gray-50 dark:bg-gray-800 rounded">
                  <p className="text-xs text-gray-600 dark:text-gray-400 mb-1">Answer:</p>
                  <p className="question-answer text-sm text-gray-800 dark:text-gray-200">{question.answer}</p>
                  {question.seen && question.seenAt && !isScreenshots && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                      Seen on {formatDate(new Date(question.seenAt))} at{' '}
                      {new Date(question.seenAt).toLocaleTimeString()}
                    </p>
                  )}
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
                        <div>{question.visitorId ? `Visitor: ${question.visitorId}` : 'No Visitor ID'}</div>
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
  seen?: boolean;
  seenAt?: string;
};

type Props = {
  time: Date;
  questions: Question[];
  isAdmin?: boolean;
  adminCredential?: string;
  mode?: string;
  visitorId?: string;
};

export function Questions({ time: _time, questions, isAdmin, adminCredential, mode, visitorId }: Props) {
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
            className={`w-full rounded border p-3 ${
              question.answer && !question.seen
                ? 'border-yellow-300 bg-yellow-50 dark:border-yellow-600 dark:bg-yellow-900/20'
                : 'border-gray-200 dark:border-gray-800 dark:bg-blue-opaque'
            }`}
            key={question._id}
          >
            <div className="question gap-1">
              <div className="mb-1 flex gap-2">
                {question.answer && (
                  <span
                    className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                      question.seen
                        ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                        : 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200'
                    }`}
                  >
                    {question.seen ? 'Answered' : 'New Answer!'}
                  </span>
                )}
              </div>
              <div className="mb-2">
                <p className="question-text text-sm text-black dark:text-white">{question.question}</p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  Asked on {formatDate(new Date(question.createdAt))} at{' '}
                  {new Date(question.createdAt).toLocaleTimeString()}
                </p>
              </div>
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

function formatDate(date: Date) {
  const day = date.getDate();
  const month = date.toLocaleDateString('en-US', { month: 'long' });

  // Add ordinal suffix to day
  const getOrdinalSuffix = (day: number) => {
    if (day >= 11 && day <= 13) {
      return 'th';
    }
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  };

  return `${day}${getOrdinalSuffix(day)} ${month}`;
}
