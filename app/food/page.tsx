"use client";

import Image from "next/image";
import Link from "next/link";
import { useMemo, useState } from "react";

const delicacies = [
  "African",
  "Chinese",
  "Italian",
  "Swahili",
  "Luhya",
  "Kikuyu",
  "Coastal",
  "Mijikenda",
  "Kisii",
  "Luo",
  "Maasai",
  "Oromo / Pokomo",
  "Kamba",
  "Meru",
  "Turkana",
  "Somali",
  "Arab",
  "Ethiopian",
  "Turkish",
];

const foodItems = [
  {
    name: "Swahili Chicken Biryani",
    restaurant: "Mama Amina's Kitchen",
    location: "Mombasa",
    price: "KSh 650",
    emoji: "🍛",
    category: "Swahili",
  },
  {
    name: "Grilled Chicken",
    restaurant: "Bingo Grill House",
    location: "Nairobi",
    price: "KSh 800",
    emoji: "🍗",
    category: "African",
  },
  {
    name: "Pilau Special",
    restaurant: "Coastal Kitchen",
    location: "Mombasa",
    price: "KSh 500",
    emoji: "🍲",
    category: "Coastal",
  },
  {
    name: "Nyama Choma",
    restaurant: "Kenya BBQ",
    location: "Nakuru",
    price: "KSh 1,200",
    emoji: "🥩",
    category: "African",
  },
  {
    name: "Chapati & Beef Stew",
    restaurant: "Mama's Pot",
    location: "Kisumu",
    price: "KSh 450",
    emoji: "🥘",
    category: "Luo",
  },
  {
    name: "Fresh Seafood Platter",
    restaurant: "Bingo Ocean View",
    location: "Mombasa",
    price: "KSh 1,500",
    emoji: "🦐",
    category: "Coastal",
  },
];

export default function FoodPage() {
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<string[]>([]);

  const toggleDelicacy = (name: string) => {
    setSelected((current) =>
      current.includes(name)
        ? current.filter((item) => item !== name)
        : [...current, name]
    );
  };

  const filteredFood = useMemo(() => {
    const term = search.trim().toLowerCase();

    return foodItems.filter((item) => {
      const matchesSearch =
        !term ||
        item.name.toLowerCase().includes(term) ||
        item.restaurant.toLowerCase().includes(term) ||
        item.location.toLowerCase().includes(term) ||
        item.category.toLowerCase().includes(term);

      const matchesDelicacy =
        selected.length === 0 || selected.includes(item.category);

      return matchesSearch && matchesDelicacy;
    });
  }, [search, selected]);

  return (
    <main className="min-h-screen bg-[#0B0E14] text-white">
      <header className="sticky top-0 z-50 border-b border-cyan-500/20 bg-[#0B0E14]/95 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-3">
          <div className="flex items-center gap-4">
            <Link
              href="/"
              className="rounded-lg border border-white/10 bg-[#151C28] px-3 py-2 text-sm font-bold text-slate-200 transition hover:border-cyan-400"
            >
              ← Back
            </Link>

            <Link href="/">
              <Image
                src="/assets/bingo-original-logo.png"
                alt="Bingo"
                width={150}
                height={60}
                priority
                className="h-auto w-[125px]"
              />
            </Link>
          </div>

          <div className="flex items-center gap-2">
            <Link
              href="/"
              className="hidden rounded-lg border border-cyan-400/40 px-3 py-2 text-sm font-bold text-cyan-300 transition hover:bg-cyan-400/10 sm:block"
            >
              Home Feed
            </Link>

            <button
              type="button"
              className="rounded-lg border border-pink-400/50 bg-pink-400/10 px-3 py-2 text-sm font-bold text-pink-300"
            >
              My Food Business
            </button>
          </div>
        </div>
      </header>

      <section className="mx-auto max-w-7xl px-4 py-6">
        <div className="overflow-hidden rounded-2xl border border-yellow-500/30 bg-[#151C28]">
          <div className="border-b border-white/10 p-5 md:p-7">
            <div className="flex flex-col justify-between gap-5 md:flex-row md:items-center">
              <div>
                <div className="text-xs font-black uppercase tracking-[0.24em] text-yellow-400">
                  Bingo Food & Home Delivery
                </div>

                <h1 className="mt-2 text-3xl font-black md:text-4xl">
                  Discover Food Near You
                </h1>

                <p className="mt-2 max-w-2xl text-sm text-slate-300">
                  Browse meals, restaurants and food businesses from across
                  Kenya. Order directly from the business on Bingo.
                </p>
              </div>

              <button
                type="button"
                className="rounded-xl border border-cyan-400 bg-cyan-400/10 px-5 py-3 text-sm font-black text-cyan-300 shadow-[0_0_22px_rgba(34,211,238,0.12)] transition hover:bg-cyan-400/20"
              >
                + Add Food Business
              </button>
            </div>
          </div>

          <div className="p-5 md:p-7">
            <div className="flex flex-col gap-3 md:flex-row">
              <div className="flex flex-1 items-center rounded-xl border border-cyan-500/25 bg-[#0B0E14] px-4">
                <span className="mr-3">🔎</span>

                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search food, restaurant, delicacy or location..."
                  className="w-full bg-transparent py-3 text-sm text-white outline-none placeholder:text-slate-500"
                />
              </div>

              <button
                type="button"
                className="rounded-xl border border-green-400/40 bg-green-400/10 px-5 py-3 text-sm font-bold text-green-300"
              >
                📍 Near Me
              </button>
            </div>

            <div className="mt-5">
              <div className="mb-3 flex items-center justify-between">
                <h2 className="font-black">Choose Delicacies</h2>

                {selected.length > 0 && (
                  <button
                    type="button"
                    onClick={() => setSelected([])}
                    className="text-xs font-bold text-cyan-300"
                  >
                    Clear filters
                  </button>
                )}
              </div>

              <div className="flex flex-wrap gap-2">
                {delicacies.map((name) => {
                  const active = selected.includes(name);

                  return (
                    <label
                      key={name}
                      className={`cursor-pointer rounded-full border px-3 py-2 text-xs font-bold transition ${
                        active
                          ? "border-green-400 bg-green-400/15 text-green-300"
                          : "border-white/10 bg-[#0B0E14] text-slate-300 hover:border-cyan-400/50"
                      }`}
                    >
                      <input
                        type="checkbox"
                        checked={active}
                        onChange={() => toggleDelicacy(name)}
                        className="mr-2 accent-green-400"
                      />

                      {name}
                    </label>
                  );
                })}
              </div>
            </div>
          </div>
        </div>

        <div className="mt-7 flex items-center justify-between">
          <div>
            <h2 className="text-xl font-black">Food Feed</h2>
            <p className="text-xs text-slate-400">
              Food posted by restaurants and food businesses
            </p>
          </div>

          <span className="rounded-full border border-cyan-500/30 bg-cyan-500/10 px-3 py-1 text-xs font-black text-cyan-300">
            {filteredFood.length} ITEMS
          </span>
        </div>

        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {filteredFood.map((item) => (
            <article
              key={`${item.restaurant}-${item.name}`}
              className="overflow-hidden rounded-2xl border border-white/10 bg-[#151C28] transition hover:border-cyan-400/40"
            >
              <div className="flex h-52 items-center justify-center bg-gradient-to-br from-[#192334] to-[#0B0E14] text-7xl">
                {item.emoji}
              </div>

              <div className="p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <h3 className="font-black">{item.name}</h3>

                    <p className="mt-1 text-sm font-bold text-cyan-300">
                      {item.restaurant}
                    </p>
                  </div>

                  <span className="whitespace-nowrap text-sm font-black text-yellow-400">
                    {item.price}
                  </span>
                </div>

                <div className="mt-3 flex items-center justify-between text-xs text-slate-400">
                  <span>📍 {item.location}</span>
                  <span>{item.category}</span>
                </div>

                <div className="mt-4 grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    className="rounded-lg border border-green-400 bg-green-400/10 px-3 py-2 text-sm font-black text-green-300 transition hover:bg-green-400/20"
                  >
                    Order Now
                  </button>

                  <button
                    type="button"
                    className="rounded-lg border border-cyan-400/50 bg-cyan-400/10 px-3 py-2 text-sm font-black text-cyan-300 transition hover:bg-cyan-400/20"
                  >
                    View Restaurant
                  </button>
                </div>
              </div>
            </article>
          ))}
        </div>

        {filteredFood.length === 0 && (
          <div className="mt-4 rounded-2xl border border-white/10 bg-[#151C28] p-10 text-center">
            <div className="text-4xl">🍽️</div>
            <h3 className="mt-3 font-black">No matching food found</h3>
            <p className="mt-1 text-sm text-slate-400">
              Change your search or delicacy filters.
            </p>
          </div>
        )}

        <section className="mt-8 overflow-hidden rounded-2xl border border-pink-500/30 bg-[#151C28]">
          <div className="border-b border-white/10 p-5">
            <div className="text-xs font-black uppercase tracking-[0.2em] text-pink-400">
              Restaurant Profile Preview
            </div>

            <h2 className="mt-1 text-2xl font-black">
              Mama Amina&apos;s Kitchen
            </h2>

            <p className="mt-1 text-sm text-slate-400">
              Swahili • Coastal • Home Delivery • Mombasa
            </p>
          </div>

          <div className="grid gap-5 p-5 lg:grid-cols-[1fr_320px]">
            <div>
              <div className="flex flex-wrap gap-2">
                {[
                  "🛒 Order Now",
                  "💬 WhatsApp",
                  "📞 Call",
                  "✉️ Inbox",
                  "📍 Directions",
                  "↗ Share",
                  "🔖 Save",
                  "⚑ Report",
                ].map((action) => (
                  <button
                    type="button"
                    key={action}
                    className="rounded-lg border border-cyan-400/30 bg-[#0B0E14] px-3 py-2 text-xs font-bold text-slate-200 transition hover:border-cyan-400 hover:text-cyan-300"
                  >
                    {action}
                  </button>
                ))}
              </div>

              <div className="mt-5 flex gap-2 overflow-x-auto pb-2">
                {["Popular", "Main Meals", "Breakfast", "Drinks", "Desserts"].map(
                  (tab, index) => (
                    <button
                      type="button"
                      key={tab}
                      className={`whitespace-nowrap rounded-full px-4 py-2 text-xs font-bold ${
                        index === 0
                          ? "bg-cyan-400 text-[#071018]"
                          : "border border-white/10 bg-[#0B0E14] text-slate-300"
                      }`}
                    >
                      {tab}
                    </button>
                  )
                )}
              </div>

              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                {[
                  ["Chicken Biryani", "KSh 650", "🍛"],
                  ["Beef Pilau", "KSh 550", "🍲"],
                  ["Coconut Fish", "KSh 900", "🐟"],
                  ["Viazi Karai", "KSh 250", "🥔"],
                ].map(([name, price, icon]) => (
                  <div
                    key={name}
                    className="flex items-center gap-3 rounded-xl border border-white/10 bg-[#0B0E14] p-3"
                  >
                    <div className="text-3xl">{icon}</div>

                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm font-black">{name}</div>
                      <div className="text-xs font-bold text-yellow-400">
                        {price}
                      </div>
                    </div>

                    <button
                      type="button"
                      className="h-8 w-8 rounded-full border border-green-400 text-lg font-black text-green-300"
                    >
                      +
                    </button>
                  </div>
                ))}
              </div>
            </div>

            <aside className="rounded-xl border border-yellow-500/30 bg-[#0B0E14] p-4">
              <div className="flex items-center justify-between">
                <h3 className="font-black">Your Basket</h3>
                <span>🛒</span>
              </div>

              <div className="mt-4 border-b border-white/10 pb-4">
                <div className="flex justify-between text-sm">
                  <span>Chicken Biryani × 1</span>
                  <strong>KSh 650</strong>
                </div>
              </div>

              <div className="space-y-2 py-4 text-sm">
                <div className="flex justify-between text-slate-400">
                  <span>Subtotal</span>
                  <span>KSh 650</span>
                </div>

                <div className="flex justify-between text-slate-400">
                  <span>Delivery</span>
                  <span>Calculated at checkout</span>
                </div>

                <div className="flex justify-between border-t border-white/10 pt-3 text-base font-black">
                  <span>Total</span>
                  <span className="text-yellow-400">KSh 650</span>
                </div>
              </div>

              <button
                type="button"
                className="w-full rounded-xl border border-green-400 bg-green-400/15 px-4 py-3 text-sm font-black text-green-300"
              >
                Review Order
              </button>
            </aside>
          </div>
        </section>

        <div className="mt-8 rounded-2xl border border-cyan-500/20 bg-[#151C28] p-5">
          <h2 className="font-black">Food Business Management</h2>

          <p className="mt-2 text-sm text-slate-400">
            Restaurant owners and authorized managers will manage menu items,
            incoming orders and order progress here. Payment and M-Pesa
            controls remain restricted to the business administrator.
          </p>

          <div className="mt-4 grid gap-2 sm:grid-cols-4">
            {[
              "Order Placed",
              "Ongoing",
              "Finished / Packed",
              "Dispatched",
            ].map((status, index) => (
              <div
                key={status}
                className="rounded-xl border border-green-500/25 bg-green-500/5 p-3"
              >
                <div className="text-xs font-black text-green-300">
                  {index + 1}
                </div>
                <div className="mt-1 text-sm font-bold">{status}</div>
              </div>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
}
