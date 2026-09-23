"use client";

import Image from "next/image";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "./supabase/lib/supabase";

const sections = [
  { name: "Food", href: "/food", icon: "🍽️" },
  { name: "Posts", href: "/posts", icon: "✚" },
  { name: "Messenger", href: "/messenger", icon: "💬" },
  { name: "Boost", href: "/boost", icon: "🚀" },
];

type FeedItem = {
  id: string;
  source: "food" | "post";
  title: string;
  body: string;
  businessName?: string;
  category?: string;
  price?: number | null;
  currency?: string;
  image?: string | null;
  video?: string | null;
  createdAt: string;
};

function formatMoney(
  value?: number | null,
  currency: string = "KES"
) {
  if (value === null || value === undefined) return "";

  try {
    return new Intl.NumberFormat("en-KE", {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
    }).format(value);
  } catch {
    return `KSh ${Number(value).toLocaleString()}`;
  }
}

function getImageFromFood(item: any): string | null {
  if (Array.isArray(item?.image_urls) && item.image_urls.length > 0) {
    return item.image_urls[0];
  }

  if (typeof item?.image_url === "string" && item.image_url) {
    return item.image_url;
  }

  if (Array.isArray(item?.media)) {
    const image = item.media.find(
      (media: any) =>
        media?.type === "image" ||
        media?.mimeType?.startsWith?.("image/")
    );

    return image?.url || image?.publicUrl || null;
  }

  return null;
}

function getVideoFromFood(item: any): string | null {
  if (typeof item?.video_url === "string" && item.video_url) {
    return item.video_url;
  }

  if (Array.isArray(item?.media)) {
    const video = item.media.find(
      (media: any) =>
        media?.type === "video" ||
        media?.mimeType?.startsWith?.("video/")
    );

    return video?.url || video?.publicUrl || null;
  }

  return null;
}

function getPostImage(post: any): string | null {
  if (typeof post?.image_url === "string" && post.image_url) {
    return post.image_url;
  }

  if (Array.isArray(post?.image_urls) && post.image_urls.length > 0) {
    return post.image_urls[0];
  }

  if (typeof post?.media_url === "string") {
    const mediaType = post?.media_type || "";

    if (!mediaType || mediaType.startsWith("image")) {
      return post.media_url;
    }
  }

  return null;
}

function getPostVideo(post: any): string | null {
  if (typeof post?.video_url === "string" && post.video_url) {
    return post.video_url;
  }

  if (
    typeof post?.media_url === "string" &&
    String(post?.media_type || "").startsWith("video")
  ) {
    return post.media_url;
  }

  return null;
}

export default function Home() {
  const [feed, setFeed] = useState<FeedItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const loadHomeFeed = useCallback(async () => {
    setLoading(true);
    setError("");

    try {
      /*
       * FOOD
       *
       * We use the live schema already confirmed in Supabase:
       * food_menu_items:
       * id
       * business_id
       * item_name
       * category
       * description
       * price
       * currency
       * image_urls
       * video_url
       * is_available
       * status
       * created_at
       */
      const foodRequest = supabase
        .from("food_menu_items")
        .select(`
          id,
          business_id,
          item_name,
          category,
          description,
          price,
          currency,
          image_urls,
          video_url,
          is_available,
          status,
          created_at,
          food_businesses (
            business_name
          )
        `)
        .eq("status", "published")
        .eq("is_available", true)
        .order("created_at", { ascending: false })
        .limit(40);

      /*
       * POSTS
       *
       * Posts are loaded separately so a failure in Posts does not
       * prevent Food from appearing on Home.
       */
      const postsRequest = supabase
        .from("posts")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(40);

      const [foodResult, postsResult] = await Promise.all([
        foodRequest,
        postsRequest,
      ]);

      const combined: FeedItem[] = [];

      if (foodResult.error) {
        console.error("Food feed error:", foodResult.error);
      } else {
        for (const item of foodResult.data || []) {
          const businessRelation: any = item.food_businesses;

          const businessName =
            Array.isArray(businessRelation)
              ? businessRelation[0]?.business_name
              : businessRelation?.business_name;

          combined.push({
            id: `food-${item.id}`,
            source: "food",
            title: item.item_name || "Food Item",
            body: item.description || "",
            businessName: businessName || "Bingo Restaurant",
            category: item.category || "Food",
            price:
              item.price === null || item.price === undefined
                ? null
                : Number(item.price),
            currency: item.currency || "KES",
            image: getImageFromFood(item),
            video: getVideoFromFood(item),
            createdAt: item.created_at || new Date(0).toISOString(),
          });
        }
      }

      if (postsResult.error) {
        console.error("Posts feed error:", postsResult.error);
      } else {
        for (const post of postsResult.data || []) {
          /*
           * Do not show records explicitly marked as draft,
           * deleted, removed or rejected.
           *
           * If the current posts table has no status field,
           * the post remains eligible.
           */
          const status = String(post?.status || "").toLowerCase();

          if (
            ["draft", "deleted", "removed", "rejected"].includes(status)
          ) {
            continue;
          }

          combined.push({
            id: `post-${post.id}`,
            source: "post",
            title:
              post.title ||
              post.post_title ||
              post.category ||
              "Bingo Post",
            body:
              post.body ||
              post.content ||
              post.description ||
              post.text ||
              "",
            category: post.category || "",
            image: getPostImage(post),
            video: getPostVideo(post),
            createdAt: post.created_at || new Date(0).toISOString(),
          });
        }
      }

      combined.sort(
        (a, b) =>
          new Date(b.createdAt).getTime() -
          new Date(a.createdAt).getTime()
      );

      setFeed(combined);

      if (foodResult.error && postsResult.error) {
        setError("Home Feed could not be loaded.");
      }
    } catch (err) {
      console.error(err);
      setError("Home Feed could not be loaded.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadHomeFeed();
  }, [loadHomeFeed]);

  return (
    <main className="min-h-screen bg-[#0B0E14] text-white">
      <header className="sticky top-0 z-50 border-b border-cyan-500/20 bg-[#0B0E14]/95 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3">
          <Link href="/" aria-label="Bingo Home">
            <Image
              src="/assets/bingo-original-logo.png"
              alt="Bingo"
              width={150}
              height={60}
              priority
              className="h-auto w-[130px]"
            />
          </Link>

          <nav className="flex items-center gap-2">
            <Link
              href="/food"
              className="rounded-lg border border-cyan-400 px-3 py-2 text-sm font-bold hover:bg-cyan-400/10"
            >
              Food
            </Link>

            <Link
              href="/messenger"
              className="rounded-lg border border-pink-400 px-3 py-2 text-sm font-bold hover:bg-pink-400/10"
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

              <div className="mt-3 font-bold">
                {section.name}
              </div>

              <div className="mt-1 text-xs text-slate-400">
                Open {section.name}
              </div>
            </Link>
          ))}
        </div>

        <section className="mt-8">
          <div className="mb-4 flex items-center justify-between gap-4">
            <div>
              <h2 className="text-xl font-black">
                Home Feed
              </h2>

              <p className="mt-1 text-xs text-slate-400">
                Latest across Bingo
              </p>
            </div>

            <div className="flex items-center gap-3">
              <span className="hidden text-xs font-bold text-cyan-400 sm:block">
                BINGO 360VIEW
              </span>

              <button
                type="button"
                onClick={loadHomeFeed}
                className="rounded-lg border border-cyan-400/60 px-3 py-2 text-xs font-bold text-cyan-300 transition hover:bg-cyan-400/10"
              >
                Refresh
              </button>
            </div>
          </div>

          {loading && (
            <div className="flex min-h-[260px] items-center justify-center rounded-2xl border border-white/10 bg-[#151C28]">
              <div className="text-center">
                <div className="mx-auto h-9 w-9 animate-spin rounded-full border-2 border-cyan-400 border-t-transparent" />

                <p className="mt-4 text-sm text-slate-400">
                  Loading Bingo...
                </p>
              </div>
            </div>
          )}

          {!loading && error && feed.length === 0 && (
            <div className="rounded-2xl border border-red-500/30 bg-[#151C28] p-8 text-center">
              <p className="font-bold text-red-300">
                {error}
              </p>

              <button
                type="button"
                onClick={loadHomeFeed}
                className="mt-4 rounded-lg border border-cyan-400 px-4 py-2 text-sm font-bold text-cyan-300"
              >
                Try Again
              </button>
            </div>
          )}

          {!loading && !error && feed.length === 0 && (
            <div className="rounded-2xl border border-white/10 bg-[#151C28] p-10 text-center">
              <div className="text-4xl">🇰🇪</div>

              <h3 className="mt-3 text-xl font-bold">
                Welcome to Bingo
              </h3>

              <p className="mt-2 text-sm text-slate-400">
                Published posts and food will appear here.
              </p>
            </div>
          )}

          {!loading && feed.length > 0 && (
            <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
              {feed.map((item) => (
                <article
                  key={item.id}
                  className="overflow-hidden rounded-2xl border border-white/10 bg-[#151C28] shadow-xl"
                >
                  <div className="flex items-center justify-between gap-3 border-b border-white/10 p-4">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span
                          className={
                            item.source === "food"
                              ? "rounded-full border border-yellow-500/40 bg-yellow-500/10 px-2 py-1 text-[10px] font-black uppercase text-yellow-300"
                              : "rounded-full border border-cyan-500/40 bg-cyan-500/10 px-2 py-1 text-[10px] font-black uppercase text-cyan-300"
                          }
                        >
                          {item.source === "food"
                            ? "Food"
                            : "Post"}
                        </span>

                        {item.category && (
                          <span className="truncate text-xs text-slate-400">
                            {item.category}
                          </span>
                        )}
                      </div>

                      {item.businessName && (
                        <p className="mt-2 truncate text-sm font-bold text-white">
                          {item.businessName}
                        </p>
                      )}
                    </div>

                    <span className="shrink-0 text-[10px] text-slate-500">
                      {item.createdAt
                        ? new Date(item.createdAt).toLocaleDateString(
                            "en-KE"
                          )
                        : ""}
                    </span>
                  </div>

                  {item.video ? (
                    <video
                      src={item.video}
                      controls
                      playsInline
                      preload="metadata"
                      className="aspect-[4/3] w-full bg-black object-cover"
                    />
                  ) : item.image ? (
                    <div className="relative aspect-[4/3] w-full bg-black">
                      <img
                        src={item.image}
                        alt={item.title}
                        loading="lazy"
                        className="h-full w-full object-cover"
                      />
                    </div>
                  ) : null}

                  <div className="p-4">
                    <h3 className="text-lg font-black">
                      {item.title}
                    </h3>

                    {item.body && (
                      <p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-slate-300">
                        {item.body}
                      </p>
                    )}

                    {item.source === "food" &&
                      item.price !== null &&
                      item.price !== undefined && (
                        <div className="mt-4 text-lg font-black text-yellow-400">
                          {formatMoney(
                            item.price,
                            item.currency || "KES"
                          )}
                        </div>
                      )}

                    <div className="mt-5 flex flex-wrap gap-2">
                      {item.source === "food" ? (
                        <>
                          <Link
                            href="/food"
                            className="rounded-lg bg-cyan-400 px-4 py-2 text-xs font-black text-[#071018] transition hover:bg-cyan-300"
                          >
                            View Food
                          </Link>

                          <Link
                            href="/food"
                            className="rounded-lg border border-pink-400 px-4 py-2 text-xs font-bold text-pink-300 transition hover:bg-pink-400/10"
                          >
                            Order
                          </Link>
                        </>
                      ) : (
                        <Link
                          href="/posts"
                          className="rounded-lg border border-cyan-400 px-4 py-2 text-xs font-bold text-cyan-300 transition hover:bg-cyan-400/10"
                        >
                          Open Post
                        </Link>
                      )}

                      <button
                        type="button"
                        onClick={async () => {
                          try {
                            await navigator.share?.({
                              title: item.title,
                              text: item.body || item.title,
                              url: window.location.href,
                            });
                          } catch {
                            // User cancelled sharing.
                          }
                        }}
                        className="rounded-lg border border-white/20 px-4 py-2 text-xs font-bold text-slate-200 transition hover:border-white/40"
                      >
                        Share
                      </button>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
      </section>
    </main>
  );
}
