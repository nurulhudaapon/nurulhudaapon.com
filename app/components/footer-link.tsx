interface FooterLinkProps {
  icon: React.ReactNode;
  href: string;
  label: string;
}

export function FooterLink({ icon, href, label }: FooterLinkProps) {
  return (
    <a
      href={href}
      target={href.startsWith("mailto:") ? undefined : "_blank"}
      rel={href.startsWith("mailto:") ? undefined : "noopener noreferrer"}
      aria-label={label}
      className="text-neutral-600 dark:text-neutral-400 hover:text-black dark:hover:text-white transition"
    >
      {icon}
    </a>
  );
} 