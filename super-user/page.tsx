"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

const SUPER_USER_DASHBOARD =
  "/BINGO_SUPER_USER_EXACT_DASHBOARD_2026-09-22.html.html";

export default function SuperUserPage() {
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    document.title = "Bingo Super User Dashboard";
  }, []);

  return (
    <main className="min-h-screen bg-[#0B0E14] text-white">
      <header className="sticky top-0 z-50 border-b border-yellow-500/20 bg-[#0B0E14]/95 backdrop-blur">
        <div className="mx-auto flex min-h-[64px] max-w-[1600px] items-center justify-between gap-3 px-3 md:px-5">
          <div className="flex items-center gap-3">
            <Link
              href="/"
              className="rounded-lg border border-white/10 bg-[#151C28] px-3 py-2 text-sm font-bold transition hover:border-cyan-400"
            >
              ← Back
            </Link>

            <div>
              <div className="text-sm font-black text-yellow-400">
                BINGO SUPER USER
              </div>
              <div className="text-[11px] text-slate-400">
                Administration & Control
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Link
              href="/food"
              className="rounded-lg border border-cyan-400/40 px-3 py-2 text-xs font-bold transition hover:bg-cyan-400/10"
            >
              Food
            </Link>

            <Link
              href="/"
              className="rounded-lg border border-yellow-400/40 px-3 py-2 text-xs font-bold text-yellow-300 transition hover:bg-yellow-400/10"
            >
              Bingo Home
            </Link>
          </div>
        </div>
      </header>

      <section className="relative h-[calc(100vh-64px)] w-full overflow-hidden bg-[#0B0E14]">
        {!loaded && (
          <div className="absolute inset-0 z-10 flex items-center justify-center bg-[#0B0E14]">
            <div className="text-center">
              <div className="mx-auto h-10 w-10 animate-spin rounded-full border-4 border-yellow-400/20 border-t-yellow-400" />

              <div className="mt-4 text-sm font-bold text-yellow-300">
                Opening Bingo Super User Dashboard...
              </div>

              <div className="mt-1 text-xs text-slate-500">
                Loading approved Super User interface
              </div>
            </div>
          </div>
        )}

        <iframe
          src={SUPER_USER_DASHBOARD}
          title="Bingo Super User Dashboard"
          onLoad={() => setLoaded(true)}
          className="h-full w-full border-0 bg-[#0B0E14]"
          allow="camera; microphone; geolocation; clipboard-read; clipboard-write"
        />
      </section>
    </main>
  );
}
