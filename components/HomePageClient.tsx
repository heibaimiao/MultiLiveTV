"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import CategoryTabs from "@/components/CategoryTabs";
import MovieGrid from "@/components/MovieGrid";
import {
  getCategoryLabel,
  getParentTypeId,
} from "@/lib/categoryTree";
import type { CategoryTree } from "@/lib/categoryTree";
import type { MergedVodItem, VodItem } from "@/lib/types";
import { mergeVodItems } from "@/lib/vodMerge";

interface HomePageClientProps {
  initialTypeId: number | null;
  initialItems: Array<VodItem | MergedVodItem>;
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
  initialItems,
  initialPageCount = 1,
  categoryTree,
  sourceId,
  sourceName,
  sourceCount,
}: HomePageClientProps) {
  const router = useRouter();
  const [typeId, setTypeId] = useState(initialTypeId);
  const [items, setItems] = useState(initialItems);
  const [page, setPage] = useState(1);
  const [pageCount, setPageCount] = useState(initialPageCount);
  const [activeSourceId, setActiveSourceId] = useState(sourceId);
  const [activeSourceName, setActiveSourceName] = useState(sourceName);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const requestId = useRef(0);

  useEffect(() => {
    setTypeId(initialTypeId);
    setItems(initialItems);
    setPage(1);
    setPageCount(initialPageCount);
    setActiveSourceId(sourceId);
    setActiveSourceName(sourceName);
    setError(null);
  }, [initialTypeId, initialItems, initialPageCount, sourceId, sourceName]);

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

  const mergeItems = useCallback(
    (
      prev: Array<VodItem | MergedVodItem>,
      next: Array<VodItem | MergedVodItem>
    ) => {
      const flatten = (items: Array<VodItem | MergedVodItem>) =>
        items.flatMap((item) => {
          if ("variants" in item && item.variants.length > 0) {
            return item.variants.map((variant) => ({
              ...item,
              vod_id: variant.vodId,
              sourceId: variant.sourceId,
              sourceName: variant.sourceName,
            }));
          }

          return [
            {
              ...item,
              sourceId: activeSourceId,
              sourceName: activeSourceName,
            },
          ];
        });

      return mergeVodItems([...flatten(prev), ...flatten(next)]);
    },
    [activeSourceId, activeSourceName]
  );

  const loadType = useCallback(
    async (nextTypeId: number | null) => {
      const currentRequest = ++requestId.current;
      setTypeId(nextTypeId);
      setError(null);
      setPage(1);

      router.replace(nextTypeId ? `/?t=${nextTypeId}` : "/", { scroll: false });

      try {
        const response = await fetch(buildListUrl(nextTypeId, 1));
        if (!response.ok) throw new Error("加载失败");
        const data = await response.json();
        if (currentRequest !== requestId.current) return;

        const list = data.list ?? [];
        if (data.source?.id) {
          setActiveSourceId(data.source.id);
          setActiveSourceName(data.source.name);
        }
        setItems(list);
        setPage(data.page ?? 1);
        setPageCount(data.pagecount ?? 1);
        if (!list.length) {
          setError(
            nextTypeId === null
              ? "暂无内容，请稍后重试"
              : `当前分类「${getCategoryLabel(categoryTree, nextTypeId)}」暂无内容`
          );
        }
      } catch {
        if (currentRequest !== requestId.current) return;
        setError("加载失败，请稍后重试");
        setItems([]);
        setPageCount(1);
      }
    },
    [buildListUrl, categoryTree, router]
  );

  const loadMore = useCallback(async () => {
    if (isLoadingMore || page >= pageCount) return;

    const nextPage = page + 1;
    setIsLoadingMore(true);

    try {
      const response = await fetch(
        buildListUrl(typeId, nextPage, activeSourceId)
      );
      if (!response.ok) throw new Error("加载失败");
      const data = await response.json();
      const list = data.list ?? [];
      setItems((prev) => mergeItems(prev, list));
      setPage(data.page ?? nextPage);
      setPageCount(data.pagecount ?? pageCount);
    } catch {
      setError("加载更多失败，请稍后重试");
    } finally {
      setIsLoadingMore(false);
    }
  }, [
    activeSourceId,
    buildListUrl,
    isLoadingMore,
    mergeItems,
    page,
    pageCount,
    typeId,
  ]);

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
            当前源：{activeSourceName} · 共 {sourceCount} 个可用源
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
            items={items}
            sourceId={activeSourceId}
            sourceName={activeSourceName}
          />
          {page < pageCount ? (
            <div className="flex justify-center">
              <button
                type="button"
                onClick={() => void loadMore()}
                disabled={isLoadingMore}
                className="rounded-full border border-[var(--border)] bg-[var(--card)] px-6 py-2.5 text-sm text-[var(--foreground)] transition hover:border-[var(--accent)] hover:text-[var(--accent)] disabled:cursor-not-allowed disabled:opacity-60"
              >
                {isLoadingMore ? "加载中..." : `加载更多（${page}/${pageCount}）`}
              </button>
            </div>
          ) : null}
        </div>
      )}
    </div>
  );
}
