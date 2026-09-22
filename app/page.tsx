import Image from "next/image";
import Link from "next/link";

const sections = [
  { name: "Food", href: "/food", icon: "🍽️" },
  { name: "Posts", href: "/posts", icon: "✚" },
  { name: "Messenger", href: "/messenger", icon: "💬" },
  { name: "Boost", href: "/boost", icon: "🚀" },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-[#0B0E14] text-white">
      <header className="sticky top-0 z-50 border-b border-cyan-500/20 bg-[#0B0E14]/95 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3">
          <Image
            src="/assets/bingo-original-logo.png"
            alt="Bingo"
            width={150}
            height={60}
            priority
            className="h-auto w-[130px]"
          />

          <nav className="flex items-center gap-2">
            <Link
              href="/food"
              className="rounded-lg border border-cyan-400 px-3 py-2 text-sm hover:bg-cyan-400/10"
            >
              Food
            </Link>

            <Link
              href="/messenger"
              className="rounded-lg border border-pink-400 px-3 py-2 text-sm hover:bg-pink-400/10"
            >
              Messenger
            </Link>
          </nav>
        </div>
      </header>

      <section className="mx-auto max-w-7xl px-4 py-8">
        <div className="rounded-2xl border border-yellow-500/30 bg-[#151C28] p-6">
          <p className="text-xs font-bold uppercase tracking-[0.25em] text-yellow-400">
            Bingo Kenya
          </p>

          <h1 className="mt-2 text-3xl font-black md:text-5xl">
            All Kenyans, One Market
          </h1>

          <p className="mt-3 max-w-2xl text-sm text-slate-300 md:text-base">
            Discover businesses, food, property, vehicles, services,
            conversations and opportunities across Bingo.
          </p>
        </div>

        <div className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-4">
          {sections.map((section) => (
            <Link
              key={section.name}
              href={section.href}
              className="rounded-xl border border-cyan-500/25 bg-[#151C28] p-5 transition hover:border-cyan-400 hover:bg-[#192334]"
            >
              <div className="text-2xl">{section.icon}</div>
              <div className="mt-3 font-bold">{section.name}</div>
              <div className="mt-1 text-xs text-slate-400">
                Open {section.name}
              </div>
            </Link>
          ))}
        </div>

        <section className="mt-6">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-xl font-bold">Home Feed</h2>
            <span className="text-xs font-bold text-cyan-400">
              BINGO 360VIEW
            </span>
          </div>

          <div className="flex min-h-[420px] items-center justify-center rounded-2xl border border-white/10 bg-[#151C28] p-8 text-center">
            <div>
              <div className="text-4xl">🇰🇪</div>
              <h3 className="mt-3 text-xl font-bold">
                Bingo Next.js is ready
              </h3>
              <p className="mt-2 text-sm text-slate-400">
                The existing Bingo Home Feed will be connected here without
                removing the current Supabase functionality.
              </p>
            </div>
          </div>
        </section>
      </section>
    </main>
  );
}
