"use client";

import type { PlaySource } from "@/lib/types";

interface SourceTabsProps {
  playSources: PlaySource[];
  activeIndex: number;
  onSelect: (index: number) => void;
}

export default function SourceTabs({
  playSources,
  activeIndex,
  onSelect,
}: SourceTabsProps) {
  if (playSources.length <= 1) return null;

  return (
    <div className="flex gap-2 overflow-x-auto pb-1">
      {playSources.map((source, index) => (
        <button
          key={source.key}
          type="button"
          onClick={() => onSelect(index)}
          className={`shrink-0 rounded-full px-4 py-1.5 text-sm transition ${
            index === activeIndex
              ? "bg-[var(--accent)] text-white"
              : "bg-[var(--card)] text-[var(--muted)] hover:text-white"
          }`}
        >
          {source.name}
        </button>
      ))}
    </div>
  );
}
