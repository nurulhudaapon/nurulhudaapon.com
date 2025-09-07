'use client';
import { useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';

export function Cmd(props: {
  cmd: Pick<KeyboardEvent, 'key' | 'altKey' | 'ctrlKey' | 'metaKey' | 'shiftKey'>;
  onCmd?: (cmd: string) => void;
  params?: { [key: string]: string };
}) {
  const router = useRouter();
  const searchParams = useSearchParams();

  const updateParams = (newParams: { [key: string]: string }) => {
    const currentParams = new URLSearchParams(searchParams.toString());

    // Add or update the new parameters
    Object.entries(newParams).forEach(([key, value]) => {
      currentParams.set(key, value);
    });

    // Build the new URL with updated parameters
    const newUrl = `${window.location.pathname}?${currentParams.toString()}`;

    // Navigate to the new URL
    router.push(newUrl);
  };

  useEffect(() => {
    const handleKeyPress = (event: KeyboardEvent) => {
      // Check if the pressed key matches the specified cmd
      const matchesCmd =
        event.key === props.cmd.key &&
        event.altKey === props.cmd.altKey &&
        event.ctrlKey === props.cmd.ctrlKey &&
        event.metaKey === props.cmd.metaKey &&
        event.shiftKey === props.cmd.shiftKey;

      if (matchesCmd) {
        props.onCmd?.(event.key);
        if (props.params) {
          updateParams(props.params);
        }
      }
    };
    window.addEventListener('keydown', handleKeyPress);
    return () => {
      window.removeEventListener('keydown', handleKeyPress);
    };
  }, [props.cmd]);

  return null;
}
