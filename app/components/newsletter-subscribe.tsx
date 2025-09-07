'use client';

import { useState } from 'react';
import { gqlClient } from '@/libs';
import { subscribeToNewsletter } from '@/libs/queries';

interface SubscribeResponse {
  data: {
    subscribeToNewsletter: {
      status: string;
    };
  } | null;
  errors?: Array<{
    message: string;
    extensions?: {
      code: string;
    };
  }>;
}

export function NewsletterSubscribe() {
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
  const [message, setMessage] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus('loading');
    setMessage('');

    try {
      const response = (await gqlClient(subscribeToNewsletter)({ email })) as SubscribeResponse;

      if (response.data?.subscribeToNewsletter?.status === 'SUCCESS') {
        setStatus('success');
        setMessage('Successfully subscribed to the newsletter!');
        setEmail('');
      } else if (response.data?.subscribeToNewsletter?.status === 'PENDING') {
        setStatus('success');
        setMessage('Please check your email to confirm your subscription.');
        setEmail('');
      } else if (response.errors?.[0]) {
        setStatus('error');
        setMessage(response.errors[0].message);
      } else {
        setStatus('error');
        setMessage('Failed to subscribe. Please try again.');
      }
    } catch (error) {
      setStatus('error');
      setMessage('An error occurred. Please try again.');
    }
  };

  return (
    <div className="bg-white dark:bg-neutral-900 p-3 rounded-lg border border-neutral-200 dark:border-neutral-800">
      <form onSubmit={handleSubmit} className="relative">
        <div className="relative">
          <label htmlFor="email" className="sr-only">
            Email address
          </label>
          <input
            id="email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="Subscribe to newsletter"
            required
            className="w-full px-3 py-1.5 pr-28 text-sm rounded-md border border-neutral-300 dark:border-neutral-700 bg-white dark:bg-neutral-800 text-black dark:text-white focus:outline-none focus:ring-2 focus:ring-neutral-500"
          />
          <button
            type="submit"
            disabled={status === 'loading'}
            className="absolute right-1 top-1/2 -translate-y-1/2 px-3 py-1 text-sm bg-neutral-200 dark:bg-neutral-700 text-neutral-700 dark:text-neutral-200 rounded hover:bg-neutral-300 dark:hover:bg-neutral-600 transition disabled:opacity-50 min-w-[100px] text-center"
          >
            {status === 'loading' ? 'Subscribing...' : 'Subscribe'}
          </button>
        </div>
      </form>
      {message && (
        <p className={`mt-2 text-sm ${status === 'success' ? 'text-green-600' : 'text-red-600'}`}>{message}</p>
      )}
    </div>
  );
}
