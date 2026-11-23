import Link from "next/link";
import { useRouter } from "next/router";

const LINKS = [
  { href: "/", label: "Live Scanner" },
  { href: "/opportunities", label: "Opportunità" },
  { href: "/history", label: "Storico Prezzi" },
  { href: "/settings", label: "Impostazioni" },
];

export default function Nav() {
  const router = useRouter();
  return (
    <nav className="nav">
      <div className="nav-brand">🃏 Pokémon Vinted Deal Scanner</div>
      <div className="nav-links">
        {LINKS.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className={router.pathname === link.href ? "nav-link active" : "nav-link"}
          >
            {link.label}
          </Link>
        ))}
      </div>
    </nav>
  );
}
