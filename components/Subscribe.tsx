import { useState, useRef } from 'react';
import useSWR from 'swr';

import fetcher from 'lib/fetcher';
import { Form, FormState, Subscribers } from 'lib/types';
import SuccessMessage from 'components/SuccessMessage';
import ErrorMessage from 'components/ErrorMessage';
import LoadingSpinner from 'components/LoadingSpinner';
import { GLOBAL_CONFIG } from './Resources';

export default function Subscribe() {
  const [form, setForm] = useState<FormState>({ state: Form.Initial });
  const inputEl = useRef(null);
  const { data } = useSWR<Subscribers>('/api/subscribers', fetcher);
  const subscriberCount = new Number(data?.count);

  if (!GLOBAL_CONFIG.enableNewsletter) return null;

  const subscribe = async (e) => {
    e.preventDefault();
    setForm({ state: Form.Loading });

    const email = inputEl.current.value;
    const res = await fetch(`/api/subscribers`, {
      method: 'POST',
      body: JSON.stringify({ email })
    });

    const { error } = await res.json();
    if (error) {
      setForm({
        state: Form.Error,
        message: error
      });
      return;
    }

    inputEl.current.value = '';
    let _form = { ...form };
    if (res.status === 200)
      _form = { state: Form.Already, message: 'You were in!' };
    else if (res.status === 201)
      _form = {
        state: Form.Success,
        message: `You are in!`
      };
    else if (res.status === 201)
      _form = { state: Form.Error, message: `Oops! Something went wrong. 😔` };
    setForm(_form);
  };
  const countText =
    subscriberCount > 0 ? subscriberCount.toLocaleString() : '-';
  return (
    <div className="border border-blue-200 rounded p-3 pt-0 my-4 w-full dark:border-gray-800 dark:bg-blue-opaque">
      <form className="relative my-4" onSubmit={subscribe}>
        <input
          ref={inputEl}
          aria-label="Email for newsletter"
          placeholder="example@mail.com"
          type="email"
          autoComplete="email"
          required
          className="px-4 py-2 mt-1b foblue-500 focuscus:ring-:border-blue-500 block w-full rounded-md bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 pr-32"
        />
        <button
          className="flex items-center justify-center absolute right-1 top-1 px-4 pt-1 font-medium h-8 bg-gray-100 dark:bg-gray-700 text-gray-900 dark:text-gray-100 rounded w-28"
          type="submit"
        >
          {form.state === Form.Loading ? <LoadingSpinner /> : 'Subscribe'}
        </button>
      </form>

      <div className="label flex justify-between">
        <div className="title ml-1 justify-start">
          <p className="text-sm font-bold text-gray-900 dark:text-gray-100">
            Subscribe to receive updates
          </p>
        </div>
        <div className="message justify-end">
          {form.state === Form.Error ? (
            <ErrorMessage>{form.message}</ErrorMessage>
          ) : form.state === Form.Success || form.state === Form.Already ? (
            <SuccessMessage>{form.message}</SuccessMessage>
          ) : (
            <p className="text-sm text-gray-800 dark:text-gray-200">
              {countText} subscribers
              <span className="relative inline-flex ml-2 w-2 h-2 rounded-full bg-green-400 animate-ping"></span>
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
