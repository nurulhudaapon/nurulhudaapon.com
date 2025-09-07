'use client';
import { useActionState, useState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import { handleQuestionSubmit } from './action';

export function Ask({
  isAdmin = false,
  questionId,
  adminCredential,
  existingAnswer,
}: {
  isAdmin?: boolean;
  questionId?: string;
  adminCredential?: string;
  existingAnswer?: string;
}) {
  const [state, formAction] = useActionState(handleQuestionSubmit, { success: false });
  const [ip, setIp] = useState();

  useEffect(() => {
    (async () => {
      const request = await fetch('https://ipinfo.io/json?token=18a8a8f700399d');
      const jsonResponse = await request.json();
      setIp(jsonResponse);
    })();
  }, []);

  return (
    <div className="w-full rounded border border-blue-200 p-3 dark:border-gray-800 dark:bg-blue-opaque">
      <form action={formAction} className="relative flex w-full flex-col gap-3">
        <div>
          <FormTextarea
            key={questionId}
            autoFocus
            name="question"
            aria-label={isAdmin && questionId ? 'Write your answer' : 'Write your question anonymously'}
            placeholder={isAdmin && questionId ? 'Write your answer here...' : 'Ask me anything...'}
            defaultValue={existingAnswer || ''}
            cols={30}
            rows={4}
            required
          />
          <input type="hidden" name="email" value="" />
          <input type="hidden" name="isAdmin" value={isAdmin.toString()} />
          {adminCredential && <input type="hidden" name="adminCredential" value={adminCredential} />}
          {questionId && <input type="hidden" name="questionId" value={questionId} />}
          <input type="hidden" name="ip" value={JSON.stringify(ip)} />
        </div>
        <div className="items-right flex w-full items-center justify-between">
          <div className="message">{/* Success/error messages will be handled via URL params */}</div>
          <FormButton
            className="flex flex-row h-8 w-28 items-center justify-center rounded border border-blue-100 bg-white px-4 font-medium text-gray-900 dark:bg-gray-700 dark:text-gray-100 hover:bg-gray-50 dark:hover:bg-gray-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            type="submit"
          >
            {isAdmin && questionId ? 'Answer' : 'Submit'}
          </FormButton>
        </div>
      </form>
    </div>
  );
}

export const FormTextarea = (props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) => {
  const { pending } = useFormStatus();
  return (
    <textarea
      disabled={pending}
      className="mt-1 block w-full rounded-md bg-white px-4 py-2 pr-32 text-gray-900 dark:bg-gray-800 dark:text-gray-100 border border-gray-300 dark:border-gray-600 focus:border-blue-500 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
      {...props}
    />
  );
};

export const FormButton = (props: React.ButtonHTMLAttributes<HTMLButtonElement>) => {
  const { pending } = useFormStatus();
  return (
    <button disabled={pending} {...props}>
      {pending ? (
        <div className="flex items-center gap-2">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-gray-300 border-t-gray-600"></div>
          {props.children}
        </div>
      ) : (
        props.children
      )}
    </button>
  );
};
