"use client";

import Link from "next/link";
import { useState } from "react";

type Post = {
  id: number;
  author: string;
  location: string;
  category: string;
  text: string;
  time: string;
  likes: number;
  comments: number;
  shares: number;
};

const demoPosts: Post[] = [
  {
    id: 1,
    author: "Bingo Kenya",
    location: "Mombasa, Kenya",
    category: "Community",
    text: "Welcome to Bingo. Discover businesses, food, property, vehicles, services and conversations from across Kenya.",
    time: "Just now",
    likes: 24,
    comments: 8,
    shares: 5,
  },
  {
    id: 2,
    author: "Mama Amina's Kitchen",
    location: "Mombasa",
    category: "Food",
    text: "Fresh coastal dishes available today. Visit our Bingo profile to view the menu, order food or contact us.",
    time: "12 min ago",
    likes: 47,
    comments: 13,
    shares: 9,
  },
];

export default function PostsPage() {
  const [posts, setPosts] = useState<Post[]>(demoPosts);
  const [composer, setComposer] = useState("");

  function publishPost() {
    const text = composer.trim();

    if (!text) return;

    const newPost: Post = {
      id: Date.now(),
      author: "You",
      location: "Kenya",
      category: "Post",
      text,
      time: "Just now",
      likes: 0,
      comments: 0,
      shares: 0,
    };

    setPosts((current) => [newPost, ...current]);
    setComposer("");
  }

  function likePost(id: number) {
    setPosts((current) =>
      current.map((post) =>
        post.id === id
          ? { ...post, likes: post.likes + 1 }
          : post
      )
    );
  }

  return (
    <main className="min-h-screen bg-[#0B0E14] text-white">
      <header className="sticky top-0 z-50 border-b border-cyan-500/20 bg-[#0B0E14]/95 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3">
          <Link href="/" className="flex items-center gap-3">
            <img
              src="/assets/bingo-original-logo.png"
              alt="Bingo"
              className="h-auto w-[125px]"
            />
          </Link>

          <div className="flex items-center gap-2">
            <Link
              href="/"
              className="rounded-lg border border-white/10 bg-[#151C28] px-3 py-2 text-sm font-bold hover:border-cyan-400"
            >
              Home
            </Link>

            <Link
              href="/food"
              className="rounded-lg border border-cyan-400/40 bg-[#151C28] px-3 py-2 text-sm font-bold text-cyan-300 hover:bg-cyan-400/10"
            >
              Food
            </Link>

            <Link
              href="/messenger"
              className="rounded-lg border border-pink-400/40 bg-[#151C28] px-3 py-2 text-sm font-bold text-pink-300 hover:bg-pink-400/10"
            >
              Messenger
            </Link>
          </div>
        </div>
      </header>

      <section className="mx-auto max-w-3xl px-4 py-6">
        <div className="mb-5 flex items-center justify-between">
          <div>
            <p className="text-xs font-black uppercase tracking-[0.25em] text-cyan-400">
              Bingo
            </p>

            <h1 className="mt-1 text-2xl font-black">
              Posts
            </h1>
          </div>

          <span className="rounded-full border border-yellow-500/30 bg-yellow-500/10 px-3 py-1 text-xs font-bold text-yellow-300">
            BINGO 360VIEW
          </span>
        </div>

        <section className="rounded-2xl border border-cyan-500/20 bg-[#151C28] p-4 shadow-xl">
          <div className="flex gap-3">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full border border-cyan-400/40 bg-[#0B0E14] font-black text-cyan-300">
              B
            </div>

            <div className="flex-1">
              <textarea
                value={composer}
                onChange={(event) => setComposer(event.target.value)}
                placeholder="What's happening on Bingo?"
                className="min-h-[110px] w-full resize-none rounded-xl border border-white/10 bg-[#0B0E14] p-4 text-sm text-white outline-none placeholder:text-slate-500 focus:border-cyan-400"
              />

              <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
                <div className="flex flex-wrap gap-2">
                  <button
                    type="button"
                    className="rounded-lg border border-cyan-500/30 px-3 py-2 text-xs font-bold text-cyan-300 hover:bg-cyan-400/10"
                  >
                    📷 Photo
                  </button>

                  <button
                    type="button"
                    className="rounded-lg border border-pink-500/30 px-3 py-2 text-xs font-bold text-pink-300 hover:bg-pink-400/10"
                  >
                    🎥 Video
                  </button>

                  <button
                    type="button"
                    className="rounded-lg border border-green-500/30 px-3 py-2 text-xs font-bold text-green-300 hover:bg-green-400/10"
                  >
                    🎵 Music
                  </button>

                  <button
                    type="button"
                    className="rounded-lg border border-yellow-500/30 px-3 py-2 text-xs font-bold text-yellow-300 hover:bg-yellow-400/10"
                  >
                    📍 Location
                  </button>
                </div>

                <button
                  type="button"
                  onClick={publishPost}
                  disabled={!composer.trim()}
                  className="rounded-xl bg-cyan-400 px-5 py-2 text-sm font-black text-[#071018] transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Publish
                </button>
              </div>
            </div>
          </div>
        </section>

        <div className="my-5 flex items-center gap-2 overflow-x-auto pb-1">
          {[
            "For You",
            "Trending",
            "Businesses",
            "Food",
            "Property",
            "Vehicles",
            "Services",
          ].map((item) => (
            <button
              key={item}
              type="button"
              className="whitespace-nowrap rounded-full border border-white/10 bg-[#151C28] px-4 py-2 text-xs font-bold text-slate-300 hover:border-cyan-400 hover:text-cyan-300"
            >
              {item}
            </button>
          ))}
        </div>

        <section className="space-y-4">
          {posts.map((post) => (
            <article
              key={post.id}
              className="overflow-hidden rounded-2xl border border-white/10 bg-[#151C28] shadow-xl"
            >
              <div className="p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex gap-3">
                    <div className="flex h-11 w-11 items-center justify-center rounded-full border border-cyan-400/40 bg-[#0B0E14] text-lg font-black text-cyan-300">
                      {post.author.charAt(0)}
                    </div>

                    <div>
                      <div className="font-black">
                        {post.author}
                      </div>

                      <div className="mt-0.5 text-xs text-slate-400">
                        {post.location} • {post.time}
                      </div>
                    </div>
                  </div>

                  <span className="rounded-full border border-cyan-500/20 bg-cyan-500/10 px-3 py-1 text-[11px] font-bold text-cyan-300">
                    {post.category}
                  </span>
                </div>

                <p className="mt-4 whitespace-pre-wrap text-[15px] leading-6 text-slate-100">
                  {post.text}
                </p>

                <div className="mt-5 grid grid-cols-4 gap-2 border-t border-white/10 pt-3">
                  <button
                    type="button"
                    onClick={() => likePost(post.id)}
                    className="rounded-lg px-2 py-2 text-xs font-bold text-slate-300 hover:bg-cyan-400/10 hover:text-cyan-300"
                  >
                    ❤️ {post.likes}
                  </button>

                  <button
                    type="button"
                    className="rounded-lg px-2 py-2 text-xs font-bold text-slate-300 hover:bg-cyan-400/10 hover:text-cyan-300"
                  >
                    💬 {post.comments}
                  </button>

                  <button
                    type="button"
                    className="rounded-lg px-2 py-2 text-xs font-bold text-slate-300 hover:bg-cyan-400/10 hover:text-cyan-300"
                  >
                    ↗️ {post.shares}
                  </button>

                  <Link
                    href="/boost"
                    className="rounded-lg px-2 py-2 text-center text-xs font-black text-yellow-300 hover:bg-yellow-400/10"
                  >
                    🚀 Boost
                  </Link>
                </div>
              </div>
            </article>
          ))}
        </section>

        <div className="mt-6 rounded-2xl border border-yellow-500/20 bg-[#151C28] p-4">
          <div className="flex items-center justify-between gap-4">
            <div>
              <div className="font-black text-yellow-300">
                🏆 Bingo Impact Awards
              </div>

              <p className="mt-1 text-xs leading-5 text-slate-400">
                Original, meaningful and sustained community engagement can
                contribute toward Bingo Impact Award recognition.
              </p>
            </div>

            <button
              type="button"
              className="shrink-0 rounded-lg border border-yellow-400/40 px-3 py-2 text-xs font-black text-yellow-300 hover:bg-yellow-400/10"
            >
              View
            </button>
          </div>
        </div>
      </section>
    </main>
  );
}
