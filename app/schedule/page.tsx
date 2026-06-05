const CALENDAR_SRC =
  'https://calendar.google.com/calendar/appointments/schedules/AcZssZ1nBnTfyZjvTSHR6mQzLHcWOD7LjCilnrpKo9YMBTaRuwOYfd5c6jrQ5511cMBjL_CNMJgVDOrk?gv=true';

const HEADER_CROP = 46; // px of the embed's own header hidden at the top

export default function Schedule() {
  return (
    <div className="space-y-6">
      <p className="text-lg text-neutral-600 dark:text-neutral-400">
        Pick a time that works for you and let&apos;s talk.
      </p>

      <div className="w-full h-[calc(100vh-13rem)] overflow-hidden bg-white dark:bg-neutral-950">
        <iframe
          src={CALENDAR_SRC}
          title="Schedule a meeting with Nurul Huda (Apon)"
          className="w-full block dark:[filter:invert(0.96)_hue-rotate(180deg)]"
          style={{
            height: `calc(100vh - 13rem + ${HEADER_CROP}px)`,
            marginTop: -HEADER_CROP,
          }}
        />
      </div>
    </div>
  );
}
