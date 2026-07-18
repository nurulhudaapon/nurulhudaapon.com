import { useEffect } from 'react';

export const useGoogleLoginButton = (buttonId: string, handleCredentialResponse: (response: google.accounts.id.CredentialResponse) => void) => {
    useEffect(() => {
        const script = document.createElement('script');
        script.src = 'https://accounts.google.com/gsi/client';
        script.async = true;
        script.defer = true;
        script.onload = () => {
            window.google.accounts.id.initialize({
                client_id: process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID,
                callback: handleCredentialResponse,
            });
            window.google.accounts.id.renderButton(
                document.getElementById(buttonId),
                { theme: 'outline', text: 'signup_with', shape: 'rectangular', size: 'medium', type: 'standard' }, // customization attributes
            );
            window.google.accounts.id.prompt(); // also display the One Tap dialog
        };
        document.body.appendChild(script);
        return () => {
            document.body.removeChild(script);
        };
    }, [buttonId, handleCredentialResponse]);
};
