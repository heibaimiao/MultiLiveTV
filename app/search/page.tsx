import MovieGrid from "@/components/MovieGrid";
import { searchVod } from "@/lib/maccms";
import { getEnabledSources } from "@/lib/sources";
import type { SearchResultItem, VodItem } from "@/lib/types";

export const dynamic = "force-dynamic";

interface SearchPageProps {
  searchParams: Promise<{ wd?: string }>;
}

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const { wd } = await searchParams;
  const keyword = wd?.trim() ?? "";

  let results: SearchResultItem[] = [];

  if (keyword) {
    const sources = getEnabledSources();
    const settled = await Promise.allSettled(
      sources.map(async (source) => {
        const data = await searchVod(source, keyword);
        return (data.list ?? []).map(
          (item): SearchResultItem => ({
            ...item,
            sourceId: source.id,
            sourceName: source.name,
          })
        );
      })
    );
    results = settled.flatMap((r) => (r.status === "fulfilled" ? r.value : []));
  }

  const grouped = results.reduce<Record<number, { name: string; items: VodItem[] }>>(
    (acc, item) => {
      if (!acc[item.sourceId]) {
        acc[item.sourceId] = { name: item.sourceName, items: [] };
      }
      acc[item.sourceId].items.push(item);
      return acc;
    },
    {}
  );

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">搜索</h1>
        {keyword && (
          <p className="mt-1 text-sm text-[var(--muted)]">
            关键词「{keyword}」共找到 {results.length} 条结果
          </p>
        )}
      </div>

      {!keyword && (
        <p className="text-[var(--muted)]">在顶部搜索框输入关键词开始搜索</p>
      )}

      {keyword && results.length === 0 && (
        <p className="text-[var(--muted)]">未找到相关影片</p>
      )}

      {Object.entries(grouped).map(([sourceId, group]) => (
        <section key={sourceId} className="space-y-4">
          <h2 className="text-lg font-semibold">{group.name}</h2>
          <MovieGrid
            items={group.items}
            sourceId={Number(sourceId)}
            sourceName={group.name}
          />
        </section>
      ))}
    </div>
  );
}
