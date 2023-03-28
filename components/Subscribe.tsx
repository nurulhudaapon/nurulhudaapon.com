import { useState, useRef, useEffect } from 'react';
import useSWR from 'swr';

import fetcher from 'lib/fetcher';
import { Form, FormState, Subscribers } from 'lib/types';
import SuccessMessage from 'components/SuccessMessage';
import ErrorMessage from 'components/ErrorMessage';
import LoadingSpinner from 'components/LoadingSpinner';
import { GLOBAL_CONFIG } from './Resources';
import { apiService } from 'lib/api';

export default function Subscribe() {
    const [form, setForm] = useState<FormState>({ state: Form.Initial });
    const inputEl = useRef(null);
    const { data } = useSWR<Subscribers>('/api/subscribers', fetcher);
    const subscriberCount = new Number(data?.count);
    const [currentUser, setCurrentUser] = useState();

    useEffect(() => {
        const currentUser = JSON.parse(localStorage.getItem('user'));
        setCurrentUser(currentUser);
        console.log(currentUser);
    }, []);

    if (!GLOBAL_CONFIG.enableNewsletter) return null;

    const subscribe = async (e) => {
        e.preventDefault();
        setForm({ state: Form.Loading });

        const email = inputEl.current.value;

        if (!email) {
            setForm({
                state: Form.Error,
            });
            return;
        }

        try {
            const res = await fetch(`/api/subscribers`, {
                method: 'POST',
                body: JSON.stringify({ email }),
            });

            const { error, ...data } = await res.json();
            if (error) {
                setForm({
                    state: Form.Error,
                    message: String(error?.message),
                });
                return;
            }

            localStorage.setItem('user', JSON.stringify(data));

            inputEl.current.value = '';
            let _form = { ...form };
            if (res.status === 200) _form = { state: Form.Already, message: 'You were in!' };
            else if (res.status === 201)
                _form = {
                    state: Form.Success,
                    message: `You are in!`,
                };
            else if (res.status === 201) _form = { state: Form.Error, message: `Oops! Something went wrong. 😔` };
            setForm(_form);
        } catch (error) {
            setForm({
                state: Form.Error,
                message: 'Oops! Something went wrong. 😔',
            });
        }
    };
    const countText = subscriberCount > 0 ? subscriberCount.toLocaleString() : '-';
    return (
        <div className="my-4 w-full rounded border border-blue-200 p-3 pt-0 dark:border-gray-800 dark:bg-blue-opaque">
            <form className="relative my-4" onSubmit={subscribe}>
                <input
                    ref={inputEl}
                    aria-label="Email for newsletter"
                    placeholder="example@mail.com"
                    type="email"
                    autoComplete="email"
                    required
                    className="mt-1b foblue-500 focuscus:ring-:border-blue-500 block w-full rounded-md bg-white px-4 py-2 pr-32 text-gray-900 dark:bg-gray-800 dark:text-gray-100"
                />
                <button
                    className="absolute right-1 top-1 flex h-8 w-28 items-center justify-center rounded bg-gray-100 px-4 pt-1 font-medium text-gray-900 dark:bg-gray-700 dark:text-gray-100"
                    type="submit"
                >
                    {form.state === Form.Loading ? <LoadingSpinner /> : 'Subscribe'}
                </button>
            </form>

            <div className="label flex justify-between">
                <div className="title ml-1 justify-start">
                    <p className="text-sm font-bold text-gray-900 dark:text-gray-100">Subscribe to receive updates</p>
                </div>
                <div className="message justify-end">
                    {form.state === Form.Error ? (
                        <ErrorMessage>{form.message}</ErrorMessage>
                    ) : form.state === Form.Success || form.state === Form.Already ? (
                        <SuccessMessage>{form.message}</SuccessMessage>
                    ) : (
                        <p className="text-sm text-gray-800 dark:text-gray-200">
                            {countText} subscribers
                            <span className="relative ml-2 inline-flex h-2 w-2 animate-ping rounded-full bg-green-400"></span>
                        </p>
                    )}
                </div>
            </div>
        </div>
    );
}
