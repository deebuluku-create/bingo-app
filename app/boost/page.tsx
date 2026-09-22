"use client";

import Link from "next/link";
import { useMemo, useState } from "react";

const PRICE_PER_DAY = 500;

const boostTypes = [
  {
    id: "post",
    title: "Boost Post",
    description: "Give your Bingo post more visibility across the Home Feed.",
    icon: "🚀",
  },
  {
    id: "food",
    title: "Boost Food",
    description: "Promote a food item or restaurant post to more customers.",
    icon: "🍽️",
  },
  {
    id: "business",
    title: "Boost Business",
    description: "Increase visibility for your Bingo business profile.",
    icon: "🏪",
  },
  {
    id: "profile",
    title: "Boost Profile",
    description: "Promote your public Bingo profile across the platform.",
    icon: "👤",
  },
];

export default function BoostPage() {
  const [boostType, setBoostType] = useState("post");
  const [days, setDays] = useState(1);
  const [phone, setPhone] = useState("");
  const [target, setTarget] = useState("");
  const [status, setStatus] = useState("");

  const total = useMemo(
    () => Math.max(1, days) * PRICE_PER_DAY,
    [days]
  );

  function startBoost() {
    if (!target.trim()) {
      setStatus("Select or enter the post, profile or business you want to boost.");
      return;
    }

    if (!phone.trim()) {
      setStatus("Enter the M-Pesa phone number that will make the payment.");
      return;
    }

    setStatus(
      `Boost prepared: ${days} day${days === 1 ? "" : "s"} — KSh ${total.toLocaleString()}. M-Pesa payment connection will use the existing Bingo boost backend.`
    );
  }

  return (
    <main className="min-h-screen bg-[#0B0E14] text-white">
      <header className="sticky top-0 z-50 border-b border-cyan-500/20 bg-[#0B0E14]/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <Link href="/">
            <img
              src="/assets/bingo-original-logo.png"
              alt="Bingo"
              className="h-auto w-[125px]"
            />
          </Link>

          <nav className="flex items-center gap-2">
            <Link
              href="/"
              className="rounded-lg border border-white/10 bg-[#151C28] px-3 py-2 text-xs font-bold hover:border-cyan-400"
            >
              Home
            </Link>

            <Link
              href="/posts"
              className="rounded-lg border border-cyan-500/30 bg-[#151C28] px-3 py-2 text-xs font-bold text-cyan-300 hover:bg-cyan-400/10"
            >
              Posts
            </Link>

            <Link
              href="/food"
              className="rounded-lg border border-green-500/30 bg-[#151C28] px-3 py-2 text-xs font-bold text-green-300 hover:bg-green-400/10"
            >
              Food
            </Link>
          </nav>
        </div>
      </header>

      <section className="mx-auto max-w-5xl px-4 py-8">
        <div className="overflow-hidden rounded-3xl border border-yellow-500/30 bg-[#151C28]">
          <div className="border-b border-white/10 bg-gradient-to-r from-yellow-500/10 via-cyan-500/5 to-pink-500/10 p-6 md:p-8">
            <div className="text-xs font-black uppercase tracking-[0.3em] text-yellow-400">
              Bingo Promotion
            </div>

            <h1 className="mt-2 text-3xl font-black md:text-5xl">
              Boost
            </h1>

            <p className="mt-3 max-w-2xl text-sm leading-6 text-slate-300">
              Increase visibility for your posts, food, business or profile
              across Bingo.
            </p>

            <div className="mt-5 inline-flex items-center rounded-full border border-yellow-400/30 bg-yellow-400/10 px-4 py-2 text-sm font-black text-yellow-300">
              KSh {PRICE_PER_DAY.toLocaleString()} per boost day
            </div>
          </div>

          <div className="p-5 md:p-8">
            <h2 className="text-lg font-black">
              1. What do you want to boost?
            </h2>

            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              {boostTypes.map((item) => {
                const active = boostType === item.id;

                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setBoostType(item.id)}
                    className={`rounded-2xl border p-4 text-left transition ${
                      active
                        ? "border-cyan-400 bg-cyan-400/10"
                        : "border-white/10 bg-[#0B0E14] hover:border-cyan-500/40"
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      <div className="text-2xl">{item.icon}</div>

                      <div>
                        <div className="font-black">
                          {item.title}
                        </div>

                        <p className="mt-1 text-xs leading-5 text-slate-400">
                          {item.description}
                        </p>
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>

            <div className="mt-7">
              <label className="text-sm font-black">
                2. Select the item
              </label>

              <p className="mt-1 text-xs text-slate-400">
                Enter the Bingo post, food item, business or profile reference.
              </p>

              <input
                value={target}
                onChange={(event) => setTarget(event.target.value)}
                placeholder="Post, business, food or profile"
                className="mt-3 w-full rounded-xl border border-white/10 bg-[#0B0E14] px-4 py-3 text-sm text-white outline-none placeholder:text-slate-500 focus:border-cyan-400"
              />
            </div>

            <div className="mt-7">
              <label className="text-sm font-black">
                3. Number of boost days
              </label>

              <div className="mt-3 grid grid-cols-4 gap-2">
                {[1, 3, 7, 14].map((value) => (
                  <button
                    key={value}
                    type="button"
                    onClick={() => setDays(value)}
                    className={`rounded-xl border px-3 py-3 text-sm font-black ${
                      days === value
                        ? "border-yellow-400 bg-yellow-400/10 text-yellow-300"
                        : "border-white/10 bg-[#0B0E14] text-slate-300 hover:border-yellow-500/40"
                    }`}
                  >
                    {value} Day{value > 1 ? "s" : ""}
                  </button>
                ))}
              </div>

              <div className="mt-3 flex items-center gap-3">
                <span className="text-xs text-slate-400">
                  Custom:
                </span>

                <input
                  type="number"
                  min={1}
                  max={365}
                  value={days}
                  onChange={(event) =>
                    setDays(
                      Math.max(
                        1,
                        Number(event.target.value) || 1
                      )
                    )
                  }
                  className="w-28 rounded-lg border border-white/10 bg-[#0B0E14] px-3 py-2 text-sm outline-none focus:border-yellow-400"
                />
              </div>
            </div>

            <div className="mt-7">
              <label className="text-sm font-black">
                4. M-Pesa payment number
              </label>

              <input
                type="tel"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                placeholder="07XXXXXXXX or 2547XXXXXXXX"
                className="mt-3 w-full rounded-xl border border-green-500/20 bg-[#0B0E14] px-4 py-3 text-sm outline-none placeholder:text-slate-500 focus:border-green-400"
              />

              <p className="mt-2 text-xs leading-5 text-slate-500">
                Bingo will request payment through the secured M-Pesa boost
                service. Never enter your M-Pesa PIN on Bingo.
              </p>
            </div>

            <div className="mt-8 rounded-2xl border border-cyan-500/20 bg-[#0B0E14] p-5">
              <div className="flex items-center justify-between border-b border-white/10 pb-3">
                <span className="text-sm text-slate-400">
                  Price per day
                </span>

                <span className="font-black">
                  KSh {PRICE_PER_DAY.toLocaleString()}
                </span>
              </div>

              <div className="flex items-center justify-between border-b border-white/10 py-3">
                <span className="text-sm text-slate-400">
                  Duration
                </span>

                <span className="font-black">
                  {days} day{days === 1 ? "" : "s"}
                </span>
              </div>

              <div className="flex items-center justify-between pt-4">
                <span className="font-black">
                  Total
                </span>

                <span className="text-2xl font-black text-yellow-300">
                  KSh {total.toLocaleString()}
                </span>
              </div>
            </div>

            {status && (
              <div className="mt-4 rounded-xl border border-cyan-500/20 bg-cyan-500/10 p-4 text-sm leading-6 text-cyan-100">
                {status}
              </div>
            )}

            <button
              type="button"
              onClick={startBoost}
              className="mt-5 w-full rounded-xl bg-gradient-to-r from-yellow-400 to-yellow-300 px-5 py-4 text-base font-black text-[#071018] shadow-lg transition hover:scale-[1.01]"
            >
              🚀 Continue to M-Pesa — KSh {total.toLocaleString()}
            </button>

            <div className="mt-5 grid gap-3 md:grid-cols-3">
              <div className="rounded-xl border border-white/10 bg-[#0B0E14] p-4">
                <div className="font-black text-cyan-300">
                  Home Feed
                </div>

                <p className="mt-1 text-xs leading-5 text-slate-400">
                  Active boosted content receives elevated placement in
                  eligible Bingo feeds.
                </p>
              </div>

              <div className="rounded-xl border border-white/10 bg-[#0B0E14] p-4">
                <div className="font-black text-green-300">
                  Verified Payment
                </div>

                <p className="mt-1 text-xs leading-5 text-slate-400">
                  A boost should activate only after the server confirms the
                  M-Pesa transaction.
                </p>
              </div>

              <div className="rounded-xl border border-white/10 bg-[#0B0E14] p-4">
                <div className="font-black text-pink-300">
                  Automatic Expiry
                </div>

                <p className="mt-1 text-xs leading-5 text-slate-400">
                  Promotion ends automatically when the paid boost period is
                  completed.
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="mt-6 flex justify-center">
          <Link
            href="/posts"
            className="rounded-xl border border-cyan-500/30 bg-[#151C28] px-5 py-3 text-sm font-black text-cyan-300 hover:bg-cyan-400/10"
          >
            ← Back to Posts
          </Link>
        </div>
      </section>
    </main>
  );
}
