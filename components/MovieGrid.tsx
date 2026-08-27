import MovieCard from "./MovieCard";
import type { VodItem } from "@/lib/types";

interface MovieGridProps {
  items: VodItem[];
  sourceId: number;
  sourceName?: string;
}

export default function MovieGrid({ items, sourceId, sourceName }: MovieGridProps) {
  if (items.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-[var(--border)] p-12 text-center text-[var(--muted)]">
        暂无影片
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
      {items.map((item) => (
        <MovieCard
          key={`${sourceId}-${item.vod_id}`}
          item={item}
          sourceId={sourceId}
          sourceName={sourceName}
        />
      ))}
    </div>
  );
}
