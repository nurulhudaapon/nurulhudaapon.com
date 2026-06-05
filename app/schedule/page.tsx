import { CalendarEmbed } from './calendar-embed';

export default function Schedule() {
  return (
    <div className="space-y-6">
      <p className="text-lg text-neutral-600 dark:text-neutral-400">
        Pick a time that works for you and let&apos;s talk.
      </p>

      <CalendarEmbed />
    </div>
  );
}
