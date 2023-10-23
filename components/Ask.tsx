import { useState, useRef, useEffect, useCallback } from 'react';
import useSWR from 'swr';

import fetcher from 'lib/fetcher';
import { Form, FormState, Subscribers } from 'lib/types';
import SuccessMessage from 'components/SuccessMessage';
import ErrorMessage from 'components/ErrorMessage';
import LoadingSpinner from 'components/LoadingSpinner';
import { GLOBAL_CONFIG } from './Resources';
import { apiService } from 'lib/api';
import { useGoogleLoginButton } from 'lib/hooks/use-google-login-button';
import classNames from 'classnames';

type Props = {
    time: Date;
    selected?: any;
    handleSelection?: (question: any) => void;
};

export function Questions({ time, handleSelection, selected }: Props) {
    const [questions, setQuestions] = useState<any[]>(null);

    useEffect(() => {
        (async () => {
            await init();
        })();
    }, [time]);

    const onSelect = (q) => {
        if (!handleSelection) return;
        // const question = questions.find((q) => q._id === e.currentTarget.id);
        handleSelection(q);
    };

    const handleDelete = useCallback(
        async (e) => {
            if (e.key === 'Backspace' || e.key === 'Delete') {
                await apiService.updateQuestion({
                    id: selected._id,
                    deleted: true,
                });
                await init();
            }
        },
        [selected],
    );

    // Delete the selected on backspace or delete
    useEffect(() => {
        window.addEventListener('keydown', handleDelete);
        return () => window.removeEventListener('keydown', handleDelete);
    }, [handleDelete]);

    if (!questions?.length) return null;

    return (
        <div className="mt-4 flex w-full flex-col gap-2">
            <h4 className="font-semibold text-gray-600 dark:text-white">Your questions</h4>
            {questions.map((question) => (
                <div key={question._id} className='flex flex-row'>
                <div className='border-2 '></div>
                <div
                    onClick={() => onSelect(question)}
                    className={classNames(
                        'border-gray-200ra w-full rounded border p-3 dark:border-gray-800 dark:bg-blue-opaque',
                        handleSelection ? 'cursor-pointer' : '',
                        selected?._id === question._id && 'border-2 border-blue-400',
                    )}
                    key={question._id}
                >
                    <div className="question gap-1">
                        {question.answer && (
                            <div className="mb-1">
                                <SuccessMessage>Answered</SuccessMessage>
                            </div>
                        )}
                        <p className="question-text text-sm text-black dark:text-white">{question.question}</p>
                        <p className="question-visitor text-xs text-gray-500 dark:text-gray-300">{question.answer}</p>
                    </div>
                </div></div>
            ))}
        </div>
    );

    async function init() {
        let questions = [];
        if (!handleSelection) questions = await apiService.getQuestions();
        else questions = await apiService.getAllQuestions();

        console.log(questions);
        setQuestions(questions.sort((b, a) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()));
    }
}

export default function Ask({ added, selected }) {
    const [form, setForm] = useState<FormState>({ state: Form.Initial });
    const inputEl = useRef(null);
    const [ip, setIp] = useState();
    const [questions, setQuestions] = useState<any[]>(null);
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
            const request = await fetch('https://ipinfo.io/json?token=18a8a8f700399d');
            const jsonResponse = await request.json();
            setIp(jsonResponse);
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

        if (selected) {
            try {
                await apiService.updateQuestion({ id: selected._id, answer: question });
                setForm({
                    state: Form.Success,
                    message: `Your answer has been submitted!`,
                });
            } catch (error) {
                setForm({
                    state: Form.Error,
                    message: 'Oops! Something went wrong. 😔',
                });
            }
            added();

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

        added();
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
                <div className="items-right flex w-full items-center justify-between">
                    <div className="message">{form.state === Form.Error ? <ErrorMessage>{form.message}</ErrorMessage> : <SuccessMessage>{form.message}</SuccessMessage>}</div>
                    <button
                        className="flex flex-row h-8 w-28 items-center justify-center rounded border border-blue-100 bg-white px-4 font-medium text-gray-900 dark:bg-gray-700 dark:text-gray-100"
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
