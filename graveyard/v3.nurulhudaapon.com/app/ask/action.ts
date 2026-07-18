'use server';

import { redirect } from 'next/navigation';
import { submitQuestionServerAction, updateQuestionAnswerServerAction, deleteQuestionServerAction } from './data';

export async function handleQuestionSubmit(prev: unknown, formData: FormData) {
  const question = formData.get('question') as string;
  const email = formData.get('email') as string;
  const questionId = formData.get('questionId') as string;
  const isAdmin = formData.get('isAdmin') === 'true';
  const adminCredential = formData.get('adminCredential') as string;

  if (!question) {
    return;
  }

  let result;
  if (isAdmin && questionId) {
    // Admin answering a selected question
    result = await updateQuestionAnswerServerAction(questionId, question);
  } else {
    // Regular question submission
    const ip = JSON.parse(formData.get('ip') as string);
    result = await submitQuestionServerAction(question, email, ip);
  }

  if (result.success) {
    if (isAdmin && adminCredential) {
      // Stay in admin mode after answering
      redirect(`/ask?admin=${adminCredential}&success=true`);
    } else {
      redirect('/ask?success=true');
    }
  }

  return {
    success: !!result.success,
  };
}

export async function handleDeleteQuestion(formData: FormData) {
  const questionId = formData.get('questionId') as string;
  const adminCredential = formData.get('adminCredential') as string;

  if (!questionId) {
    return;
  }

  const result = await deleteQuestionServerAction(questionId);

  if (result.success) {
    if (adminCredential) {
      // Stay in admin mode after deleting
      redirect(`/ask?admin=${adminCredential}&deleted=true`);
    } else {
      redirect('/ask?deleted=true');
    }
  }
}
