import MovieGrid from "@/components/MovieGrid";
import { searchVod } from "@/lib/maccms";
import { getEnabledSources } from "@/lib/sources";
import { mergeVodItems } from "@/lib/vodMerge";

export const dynamic = "force-dynamic";

interface SearchPageProps {
  searchParams: Promise<{ wd?: string }>;
}

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const { wd } = await searchParams;
  const keyword = wd?.trim() ?? "";

  let results = mergeVodItems([]);

  if (keyword) {
    const sources = getEnabledSources();
    const settled = await Promise.allSettled(
      sources.map(async (source) => {
        const data = await searchVod(source, keyword);
        return (data.list ?? []).map((item) => ({
          ...item,
          sourceId: source.id,
          sourceName: source.name,
        }));
      })
    );

    const rawList = settled.flatMap((result) =>
      result.status === "fulfilled" ? result.value : []
    );
    results = mergeVodItems(rawList);
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold">搜索</h1>
        {keyword && (
          <p className="mt-1 text-sm text-[var(--muted)]">
            关键词「{keyword}」共找到 {results.length} 条结果（已跨源合并）
          </p>
        )}
      </div>

      {!keyword && (
        <p className="text-[var(--muted)]">在顶部搜索框输入关键词开始搜索</p>
      )}

      {keyword && results.length === 0 && (
        <p className="text-[var(--muted)]">未找到相关影片</p>
      )}

      {results.length > 0 && (
        <MovieGrid items={results} />
      )}
    </div>
  );
}
