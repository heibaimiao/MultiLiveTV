"use client";

import type { Episode } from "@/lib/types";

interface EpisodeListProps {
  episodes: Episode[];
  activeIndex: number;
  onSelect: (index: number) => void;
}

export default function EpisodeList({
  episodes,
  activeIndex,
  onSelect,
}: EpisodeListProps) {
  if (episodes.length === 0) {
    return (
      <p className="text-sm text-[var(--muted)]">暂无播放地址</p>
    );
  }

  return (
    <div className="grid grid-cols-4 gap-2 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10">
      {episodes.map((episode, index) => (
        <button
          key={`${episode.name}-${index}`}
          type="button"
          onClick={() => onSelect(index)}
          className={`rounded-lg border px-2 py-2 text-xs transition ${
            index === activeIndex
              ? "border-[var(--accent)] bg-[var(--accent)] text-white"
              : "border-[var(--border)] bg-[var(--card)] hover:border-[var(--accent)]"
          }`}
        >
          {episode.name}
        </button>
      ))}
    </div>
  );
}
