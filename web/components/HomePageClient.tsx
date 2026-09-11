"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import CategoryTabs from "@/components/CategoryTabs";
import HomeShelves from "@/components/HomeShelves";
import MovieGrid from "@/components/MovieGrid";
import type { HomeFeedSection } from "@/lib/bpz5";
import {
  canLoadMoreFromPool,
  getInitialDisplayCount,
  getNextDisplayCount,
  getVisibleItems,
  HOME_INITIAL_DISPLAY,
  mergeIntoPool,
} from "@/lib/homeFeed";
import {
  getCategoryLabelBySlug,
  getParentSlug,
} from "@/lib/unifiedCategories";
import type { MergedVodItem } from "@/lib/types";

interface SlugCategory {
  slug: string;
  label: string;
}

interface HomePageClientProps {
  initialSlug: string | null;
  initialPool: MergedVodItem[];
  initialPageCount?: number;
  primary: SlugCategory[];
  childrenByParent: Record<string, SlugCategory[]>;
  sourceCount: number;
  sourcesUsed?: number[];
  feedEnabled?: boolean;
  initialFeedSections?: HomeFeedSection[];
}

function MovieGridSkeleton() {
  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
      {Array.from({ length: 12 }).map((_, index) => (
        <div
          key={index}
          className="animate-pulse overflow-hidden rounded-xl bg-[var(--card)]"
        >
          <div className="aspect-[2/3] bg-zinc-800" />
          <div className="space-y-2 p-3">
            <div className="h-4 rounded bg-zinc-800" />
            <div className="h-3 w-2/3 rounded bg-zinc-800/70" />
          </div>
        </div>
      ))}
    </div>
  );
}

export default function HomePageClient({
  initialSlug,
  initialPool = [],
  initialPageCount = 1,
  primary,
  childrenByParent,
  sourceCount,
  sourcesUsed = [],
  feedEnabled = false,
  initialFeedSections = [],
}: HomePageClientProps) {
  const router = useRouter();
  const [slug, setSlug] = useState(initialSlug);
  const [pool, setPool] = useState(initialPool);
  const [displayCount, setDisplayCount] = useState(
    getInitialDisplayCount(initialPool.length)
  );
  const [apiPage, setApiPage] = useState(1);
  const [pageCount, setPageCount] = useState(initialPageCount);
  const [usedSources, setUsedSources] = useState(sourcesUsed);
  const [feedSections, setFeedSections] = useState(initialFeedSections);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const requestId = useRef(0);
  const loadMoreRef = useRef<HTMLDivElement | null>(null);
  const loadingMoreRef = useRef(false);

  const showFeed = feedEnabled && slug === null;
  const visibleItems = getVisibleItems(pool, displayCount);
  const hasMore =
    !showFeed &&
    canLoadMoreFromPool(displayCount, pool.length, apiPage, pageCount);

  useEffect(() => {
    setSlug(initialSlug);
    setPool(initialPool ?? []);
    setDisplayCount(getInitialDisplayCount((initialPool ?? []).length));
    setApiPage(1);
    setPageCount(initialPageCount);
    setUsedSources(sourcesUsed);
    setFeedSections(initialFeedSections);
    setError(null);
  }, [
    initialSlug,
    initialPool,
    initialPageCount,
    sourcesUsed,
    initialFeedSections,
  ]);

  const activeParentSlug = getParentSlug(slug);
  const secondary =
    activeParentSlug !== null ? childrenByParent[activeParentSlug] ?? [] : [];

  const buildListUrl = useCallback((nextSlug: string | null, nextPage: number) => {
    const params = new URLSearchParams({ pg: String(nextPage) });
    if (nextSlug) params.set("cat", nextSlug);
    return `/api/vod/list?${params.toString()}`;
  }, []);

  const loadFeed = useCallback(async () => {
    const currentRequest = ++requestId.current;
    setSlug(null);
    setError(null);
    setPool([]);
    setDisplayCount(0);
    router.replace("/", { scroll: false });
    try {
      const response = await fetch("/api/feed/home");
      const data = await response.json();
      if (currentRequest !== requestId.current) return;
      const sections = (data.sections ?? []) as HomeFeedSection[];
      setFeedSections(sections);
      if (!data.enabled || !sections.length) {
        setError("推荐暂不可用，请选择分类浏览");
      }
    } catch {
      if (currentRequest !== requestId.current) return;
      setError("推荐加载失败，请稍后重试");
      setFeedSections([]);
    }
  }, [router]);

  const loadType = useCallback(
    async (nextSlug: string | null) => {
      if (feedEnabled && nextSlug === null) {
        await loadFeed();
        return;
      }

      const currentRequest = ++requestId.current;
      setSlug(nextSlug);
      setError(null);
      setPool([]);
      setDisplayCount(0);
      setApiPage(1);
      setFeedSections([]);

      router.replace(nextSlug ? `/?cat=${nextSlug}` : "/", { scroll: false });

      try {
        const listSlug = nextSlug;
        const response = await fetch(buildListUrl(listSlug, 1));
        if (!response.ok) throw new Error("加载失败");
        const data = await response.json();
        if (currentRequest !== requestId.current) return;

        const incoming = (data.list ?? []) as MergedVodItem[];
        const nextPool = mergeIntoPool([], incoming, true);

        setUsedSources(data.sourcesUsed ?? []);
        setPool(nextPool);
        setDisplayCount(getInitialDisplayCount(nextPool.length));
        setApiPage(data.page ?? 1);
        setPageCount(data.pagecount ?? 1);

        if (!nextPool.length) {
          setError(
            `当前分类「${getCategoryLabelBySlug(nextSlug)}」暂无内容`
          );
        }
      } catch {
        if (currentRequest !== requestId.current) return;
        setError("加载失败，请稍后重试");
        setPool([]);
        setDisplayCount(0);
        setPageCount(1);
      }
    },
    [buildListUrl, feedEnabled, loadFeed, router]
  );

  const loadMore = useCallback(async () => {
    if (showFeed || loadingMoreRef.current) return;

    if (displayCount < pool.length) {
      setDisplayCount((current) => getNextDisplayCount(current, pool.length));
      return;
    }

    if (apiPage >= pageCount) return;

    loadingMoreRef.current = true;
    setIsLoadingMore(true);

    try {
      const nextPage = apiPage + 1;
      const response = await fetch(buildListUrl(slug, nextPage));
      if (!response.ok) throw new Error("加载失败");
      const data = await response.json();
      const incoming = (data.list ?? []) as MergedVodItem[];

      const nextPool = mergeIntoPool(pool, incoming, false);
      setPool(nextPool);
      setDisplayCount((current) => getNextDisplayCount(current, nextPool.length));
      setApiPage(data.page ?? nextPage);
      setPageCount(data.pagecount ?? pageCount);
      if (data.sourcesUsed) setUsedSources(data.sourcesUsed);
    } catch {
      setError("加载更多失败，请稍后重试");
    } finally {
      loadingMoreRef.current = false;
      setIsLoadingMore(false);
    }
  }, [apiPage, buildListUrl, displayCount, pageCount, pool, showFeed, slug]);

  useEffect(() => {
    const target = loadMoreRef.current;
    if (!target || !hasMore) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) {
          void loadMore();
        }
      },
      { rootMargin: "240px 0px" }
    );

    observer.observe(target);
    return () => observer.disconnect();
  }, [hasMore, loadMore]);

  const handleSelect = (nextSlug: string | null) => {
    if (nextSlug === slug && !error) return;
    startTransition(() => {
      void loadType(nextSlug);
    });
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">
            {showFeed
              ? "推荐"
              : slug === null
                ? "最新影片"
                : getCategoryLabelBySlug(slug)}
          </h1>
          <p className="mt-1 text-sm text-[var(--muted)]">
            {showFeed
              ? `片库推荐 · ${feedSections.length} 个分区`
              : `统一分类 · 命中 ${usedSources.length || "—"} / ${sourceCount} 个源 · 已显示 ${visibleItems.length}${
                  pool.length > visibleItems.length
                    ? ` / 已缓存 ${pool.length}`
                    : ""
                }`}
          </p>
        </div>
      </div>

      <CategoryTabs
        primary={primary}
        secondary={secondary}
        activeSlug={slug}
        activeParentSlug={activeParentSlug}
        pending={isPending}
        feedMode={feedEnabled}
        onSelect={handleSelect}
      />

      {isPending ? (
        <MovieGridSkeleton />
      ) : error && !(showFeed && feedSections.length) ? (
        <div className="rounded-xl border border-red-500/30 bg-red-500/10 p-6 text-red-300">
          {error}
        </div>
      ) : showFeed ? (
        <HomeShelves sections={feedSections} />
      ) : (
        <div className="space-y-8">
          <MovieGrid items={visibleItems} />
          {hasMore ? (
            <div
              ref={loadMoreRef}
              className="flex justify-center py-6 text-sm text-[var(--muted)]"
            >
              {isLoadingMore
                ? "加载中..."
                : displayCount < pool.length
                  ? "继续下滑加载更多"
                  : "下滑加载更多"}
            </div>
          ) : pool.length > HOME_INITIAL_DISPLAY ? (
            <p className="pb-6 text-center text-sm text-[var(--muted)]">
              已加载全部内容
            </p>
          ) : null}
        </div>
      )}
    </div>
  );
}
