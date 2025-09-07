import { useState, useEffect, useRef } from 'react';
export function Visitor({ added, selected }) {
  const [ip, setIp] = useState();

  useEffect(() => {
    (async () => {
      const request = await fetch('https://ipinfo.io/json?token=18a8a8f700399d');
      const jsonResponse = await request.json();
      setIp(jsonResponse);
    })();
  }, []);

  return null;
}
