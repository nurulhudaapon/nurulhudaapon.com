'use client';

import { useState } from 'react';

const CALENDAR_SRC =
  'https://calendar.google.com/calendar/appointments/schedules/AcZssZ1nBnTfyZjvTSHR6mQzLHcWOD7LjCilnrpKo9YMBTaRuwOYfd5c6jrQ5511cMBjL_CNMJgVDOrk?gv=true';

const HEADER_CROP = 46; // px of the embed's own header hidden at the top
const FOOTER_CROP = 0; // px of the embed's own footer (Google branding) hidden at the bottom

export function CalendarEmbed() {
  const [loaded, setLoaded] = useState(false);

  return (
    <div className="relative w-full h-[calc(100vh-13rem)] overflow-hidden bg-white dark:bg-neutral-950">
      {!loaded && (
        <div className="absolute inset-0 flex items-center justify-center" aria-hidden>
          <div className="h-8 w-8 animate-spin rounded-full border-2 border-neutral-300 border-t-neutral-600 dark:border-neutral-700 dark:border-t-neutral-300" />
        </div>
      )}

      <iframe
        src={CALENDAR_SRC}
        title="Schedule a meeting with Nurul Huda (Apon)"
        onLoad={() => setLoaded(true)}
        className="w-full block dark:[filter:invert(0.96)_hue-rotate(180deg)]"
        style={{
          height: `calc(100vh - 13rem + ${HEADER_CROP}px + ${FOOTER_CROP}px)`,
          marginTop: -HEADER_CROP,
          opacity: loaded ? 1 : 0,
          transition: 'opacity 200ms ease',
        }}
      />
    </div>
  );
}
