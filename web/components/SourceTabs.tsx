"use client";

import { useState } from "react";
import type { PlaySource } from "@/lib/types";

interface SourceTabsProps {
  playSources: PlaySource[];
  activeIndex: number;
  onSelect: (index: number) => void;
}

const VISIBLE_LIMIT = 8;

export default function SourceTabs({
  playSources,
  activeIndex,
  onSelect,
}: SourceTabsProps) {
  const [expanded, setExpanded] = useState(
    () => activeIndex >= VISIBLE_LIMIT
  );

  if (playSources.length <= 1) return null;

  const visible = expanded
    ? playSources
    : playSources.slice(0, VISIBLE_LIMIT);
  const hiddenCount = playSources.length - VISIBLE_LIMIT;

  return (
    <div className="flex flex-wrap gap-2">
      {visible.map((source, index) => {
        const isOfficial = source.mode === "ticket";
        return (
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
            {isOfficial ? (
              <span className="ml-1 text-[10px] opacity-80">官方</span>
            ) : null}
          </button>
        );
      })}
      {!expanded && hiddenCount > 0 && (
        <button
          type="button"
          onClick={() => setExpanded(true)}
          className="shrink-0 rounded-full bg-[var(--card)] px-4 py-1.5 text-sm text-[var(--muted)] hover:text-white"
        >
          更多线路
        </button>
      )}
      {expanded && hiddenCount > 0 && (
        <button
          type="button"
          onClick={() => setExpanded(false)}
          className="shrink-0 rounded-full bg-[var(--card)] px-4 py-1.5 text-sm text-[var(--muted)] hover:text-white"
        >
          收起
        </button>
      )}
    </div>
  );
}
