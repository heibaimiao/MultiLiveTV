"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import CategoryTabs from "@/components/CategoryTabs";
import MovieGrid from "@/components/MovieGrid";
import {
  getCategoryLabel,
  getParentTypeId,
} from "@/lib/categoryTree";
import {
  canLoadMoreFromPool,
  getInitialDisplayCount,
  getNextDisplayCount,
  getVisibleItems,
  HOME_INITIAL_DISPLAY,
  mergeIntoPool,
} from "@/lib/homeFeed";
import type { CategoryTree } from "@/lib/categoryTree";
import type { MergedVodItem } from "@/lib/types";

interface HomePageClientProps {
  initialTypeId: number | null;
  initialPool: MergedVodItem[];
  initialPageCount?: number;
  categoryTree: CategoryTree;
  sourceId: number;
  sourceName: string;
  sourceCount: number;
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
  initialTypeId,
  initialPool = [],
  initialPageCount = 1,
  categoryTree,
  sourceId,
  sourceName,
  sourceCount,
}: HomePageClientProps) {
  const router = useRouter();
  const [typeId, setTypeId] = useState(initialTypeId);
  const [pool, setPool] = useState(initialPool);
  const [displayCount, setDisplayCount] = useState(
    getInitialDisplayCount(initialPool.length)
  );
  const [apiPage, setApiPage] = useState(1);
  const [pageCount, setPageCount] = useState(initialPageCount);
  const [activeSourceId, setActiveSourceId] = useState(sourceId);
  const [activeSourceName, setActiveSourceName] = useState(sourceName);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const requestId = useRef(0);
  const loadMoreRef = useRef<HTMLDivElement | null>(null);
  const loadingMoreRef = useRef(false);

  const visibleItems = getVisibleItems(pool, displayCount);
  const hasMore = canLoadMoreFromPool(
    displayCount,
    pool.length,
    apiPage,
    pageCount
  );

  useEffect(() => {
    setTypeId(initialTypeId);
    setPool(initialPool ?? []);
    setDisplayCount(getInitialDisplayCount((initialPool ?? []).length));
    setApiPage(1);
    setPageCount(initialPageCount);
    setActiveSourceId(sourceId);
    setActiveSourceName(sourceName);
    setError(null);
  }, [initialTypeId, initialPool, initialPageCount, sourceId, sourceName]);

  const activeParentId = getParentTypeId(categoryTree, typeId);
  const secondary =
    activeParentId !== null
      ? categoryTree.childrenByParent[activeParentId] ?? []
      : [];

  const buildListUrl = useCallback(
    (nextTypeId: number | null, nextPage: number, nextSourceId?: number) => {
      const params = new URLSearchParams({ pg: String(nextPage) });
      if (nextTypeId !== null) params.set("t", String(nextTypeId));
      if (nextSourceId) params.set("sourceId", String(nextSourceId));
      return `/api/vod/list?${params.toString()}`;
    },
    []
  );

  const loadType = useCallback(
    async (nextTypeId: number | null) => {
      const currentRequest = ++requestId.current;
      setTypeId(nextTypeId);
      setError(null);
      setPool([]);
      setDisplayCount(0);
      setApiPage(1);

      router.replace(nextTypeId ? `/?t=${nextTypeId}` : "/", { scroll: false });

      try {
        const response = await fetch(buildListUrl(nextTypeId, 1));
        if (!response.ok) throw new Error("加载失败");
        const data = await response.json();
        if (currentRequest !== requestId.current) return;

        const incoming = (data.list ?? []).map((item: MergedVodItem) => ({
          ...item,
          sourceId: data.source?.id,
          sourceName: data.source?.name,
        }));
        const nextPool = mergeIntoPool([], incoming, true);

        if (data.source?.id) {
          setActiveSourceId(data.source.id);
          setActiveSourceName(data.source.name);
        }
        setPool(nextPool);
        setDisplayCount(getInitialDisplayCount(nextPool.length));
        setApiPage(data.page ?? 1);
        setPageCount(data.pagecount ?? 1);

        if (!nextPool.length) {
          setError(
            nextTypeId === null
              ? "暂无内容，请稍后重试"
              : `当前分类「${getCategoryLabel(categoryTree, nextTypeId)}」暂无内容`
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
    [buildListUrl, categoryTree, router]
  );

  const loadMore = useCallback(async () => {
    if (loadingMoreRef.current) return;

    if (displayCount < pool.length) {
      setDisplayCount((current) => getNextDisplayCount(current, pool.length));
      return;
    }

    if (apiPage >= pageCount) return;

    loadingMoreRef.current = true;
    setIsLoadingMore(true);

    try {
      const nextPage = apiPage + 1;
      const response = await fetch(
        buildListUrl(typeId, nextPage, activeSourceId)
      );
      if (!response.ok) throw new Error("加载失败");
      const data = await response.json();
      const incoming = (data.list ?? []).map((item: MergedVodItem) => ({
        ...item,
        sourceId: data.source?.id ?? activeSourceId,
        sourceName: data.source?.name ?? activeSourceName,
      }));

      const nextPool = mergeIntoPool(pool, incoming, false);
      setPool(nextPool);
      setDisplayCount((current) => getNextDisplayCount(current, nextPool.length));
      setApiPage(data.page ?? nextPage);
      setPageCount(data.pagecount ?? pageCount);
    } catch {
      setError("加载更多失败，请稍后重试");
    } finally {
      loadingMoreRef.current = false;
      setIsLoadingMore(false);
    }
  }, [
    activeSourceId,
    activeSourceName,
    apiPage,
    buildListUrl,
    displayCount,
    pageCount,
    pool,
    typeId,
  ]);

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

  const handleSelect = (nextTypeId: number | null) => {
    if (nextTypeId === typeId && !error) return;
    startTransition(() => {
      void loadType(nextTypeId);
    });
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">
            {typeId === null ? "最新影片" : getCategoryLabel(categoryTree, typeId)}
          </h1>
          <p className="mt-1 text-sm text-[var(--muted)]">
            当前源：{activeSourceName} · 共 {sourceCount} 个可用源 · 已显示{" "}
            {visibleItems.length}
            {pool.length > visibleItems.length
              ? ` / 已缓存 ${pool.length}`
              : ""}
          </p>
        </div>
      </div>

      <CategoryTabs
        primary={categoryTree.primary}
        secondary={secondary}
        activeTypeId={typeId}
        activeParentId={activeParentId}
        pending={isPending}
        onSelect={handleSelect}
      />

      {isPending ? (
        <MovieGridSkeleton />
      ) : error ? (
        <div className="rounded-xl border border-red-500/30 bg-red-500/10 p-6 text-red-300">
          {error}
        </div>
      ) : (
        <div className="space-y-8">
          <MovieGrid
            items={visibleItems}
            sourceId={activeSourceId}
            sourceName={activeSourceName}
          />
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
