import { useState, useRef, useEffect } from 'react';
import useSWR from 'swr';

import fetcher from 'lib/fetcher';
import { Form, FormState, Subscribers } from 'lib/types';
import SuccessMessage from 'components/SuccessMessage';
import ErrorMessage from 'components/ErrorMessage';
import LoadingSpinner from 'components/LoadingSpinner';
import { GLOBAL_CONFIG } from './Resources';
import { apiService } from 'lib/api';
import { useGoogleLoginButton } from 'lib/hooks/use-google-login-button';

export default function Ask() {
    const [form, setForm] = useState<FormState>({ state: Form.Initial });
    const inputEl = useRef(null);
    const [ip, setIp] = useState();
    // const { data } = useSWR<Subscribers>('/api/subscribers', fetcher);
    // const subscriberCount = new Number(data?.count);
    // const [currentUser, setCurrentUser] = useState<object>();

    // useGoogleLoginButton('google-login-button', (user) => {
    //     console.log(user);
    //     setCurrentUser(user);
    // });

    // useEffect(() => {
    //     const currentUser = JSON.parse(localStorage.getItem('user'));
    //     setCurrentUser(currentUser);
    //     console.log(currentUser);
    // }, []);

    // if (!GLOBAL_CONFIG.enableNewsletter) return null;

    useEffect(() => {
        (async () => {
            const request = await fetch("https://ipinfo.io/json?token=18a8a8f700399d")
const jsonResponse = await request.json()

console.log(jsonResponse)
setIp(jsonResponse)     
        })();
    }, []);

    const subscribe = async (e) => {
        e.preventDefault();

        setForm({ state: Form.Loading });
        const email = inputEl.current.value;
        const question = inputEl.current.value;

        if (!email) {
            setForm({
                state: Form.Error,
            });
            return;
        }

        try {
            const res = await apiService.createQuestion({ question: question, email, visitor: ip });
            // if (error) {
            //     setForm({
            //         state: Form.Error,
            //         message: String(error?.message),
            //     });
            //     return;
            // }
            // localStorage.setItem('user', JSON.stringify(data));
            inputEl.current.value = '';
            // let _form = { ...form };
            // if (res.status === 200) _form = { state: Form.Already, message: 'You were in!' };
            // else if (res.status === 201)
            //     _form = {
            //         state: Form.Success,
            //         message: `You are in!`,
            //     };
            // else if (res.status === 201) _form = { state: Form.Error, message: `Oops! Something went wrong. 😔` };
            // setForm(_form);
            setForm({
                state: Form.Success,
                message: `Your question has been submitted!`,
            });
        } catch (error) {
            setForm({
                state: Form.Error,
                message: 'Oops! Something went wrong. 😔',
            });
        }
    };

    // const countText = subscriberCount > 0 ? subscriberCount.toLocaleString() : '-';
    return (
        <div className="w-full rounded border border-blue-200 p-3 dark:border-gray-800 dark:bg-blue-opaque">
            <form className="relative flex w-full flex-col gap-3" onSubmit={subscribe}>
                <div>
                    <textarea
                        autoFocus
                        ref={inputEl}
                        aria-label="Write your question anonymously"
                        // placeholder="example@mail.com"
                        // type="text"
                        name="question"
                        aria-autocomplete="list"
                        // autoComplete="email"
                        cols={30}
                        rows={4}
                        required
                        className="mt-1b foblue-500 focuscus:ring-:border-blue-500 block w-full rounded-md bg-white px-4 py-2 pr-32 text-gray-900 dark:bg-gray-800 dark:text-gray-100"
                    />
                </div>
                <div className="items-right flex w-full justify-between items-center">
                    <div className="message">{form.state === Form.Error ? <ErrorMessage>{form.message}</ErrorMessage> : <SuccessMessage>{form.message}</SuccessMessage>}</div>
                    <button
                        className="flex h-8 w-28 items-center justify-center rounded border border-blue-100 bg-white px-4 pt-1 font-medium text-gray-900 dark:bg-gray-700 dark:text-gray-100"
                        type="submit"
                    >
                        {form.state === Form.Loading ? <LoadingSpinner /> : 'Submit'}
                    </button>
                </div>
            </form>

            <div className="label flex justify-between"></div>
        </div>
    );
}
