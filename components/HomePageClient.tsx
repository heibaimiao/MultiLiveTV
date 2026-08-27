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
import type { VodItem } from "@/lib/types";

interface HomePageClientProps {
  initialTypeId: number | null;
  initialItems: VodItem[];
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
  categoryTree,
  sourceId,
  sourceName,
  sourceCount,
}: HomePageClientProps) {
  const router = useRouter();
  const [typeId, setTypeId] = useState(initialTypeId);
  const [items, setItems] = useState(initialItems);
  const [activeSourceId, setActiveSourceId] = useState(sourceId);
  const [activeSourceName, setActiveSourceName] = useState(sourceName);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const requestId = useRef(0);

  useEffect(() => {
    setTypeId(initialTypeId);
    setItems(initialItems);
    setActiveSourceId(sourceId);
    setActiveSourceName(sourceName);
    setError(null);
  }, [initialTypeId, initialItems, sourceId, sourceName]);

  const activeParentId = getParentTypeId(categoryTree, typeId);
  const secondary =
    activeParentId !== null
      ? categoryTree.childrenByParent[activeParentId] ?? []
      : [];

  const loadType = useCallback(
    async (nextTypeId: number | null) => {
      const currentRequest = ++requestId.current;
      setTypeId(nextTypeId);
      setError(null);

      const url =
        nextTypeId === null
          ? `/api/vod/list?pg=1`
          : `/api/vod/list?pg=1&t=${nextTypeId}`;

      router.replace(nextTypeId ? `/?t=${nextTypeId}` : "/", { scroll: false });

      try {
        const response = await fetch(url);
        if (!response.ok) throw new Error("加载失败");
        const data = await response.json();
        if (currentRequest !== requestId.current) return;

        const list = data.list ?? [];
        if (data.source?.id) {
          setActiveSourceId(data.source.id);
          setActiveSourceName(data.source.name);
        }
        setItems(list);
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
      }
    },
    [categoryTree, router]
  );

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
        <MovieGrid
          items={items}
          sourceId={activeSourceId}
          sourceName={activeSourceName}
        />
      )}
    </div>
  );
}
