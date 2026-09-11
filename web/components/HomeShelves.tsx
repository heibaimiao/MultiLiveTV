"use client";

import Image from "next/image";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { HomeFeedCard, HomeFeedSection } from "@/lib/bpz5";

interface HomeShelvesProps {
  sections: HomeFeedSection[];
}

function FeedCard({ card }: { card: HomeFeedCard }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function open() {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const params = new URLSearchParams({ title: card.title });
      if (card.year) params.set("year", card.year);
      const res = await fetch(`/api/vod/entry?${params}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "暂无片源");
      router.push(`/vod/${data.vodId}?source=${data.sourceId}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "打开失败");
      setBusy(false);
    }
  }

  return (
    <button
      type="button"
      onClick={() => void open()}
      disabled={busy || !card.playable}
      className="group w-[132px] shrink-0 text-left disabled:opacity-50 sm:w-[148px]"
    >
      <div className="relative aspect-[2/3] overflow-hidden rounded-xl bg-zinc-900">
        {card.poster ? (
          <Image
            src={card.poster}
            alt={card.title}
            fill
            className="object-cover transition duration-300 group-hover:scale-105"
            sizes="148px"
            unoptimized
          />
        ) : null}
        {card.remarks ? (
          <span className="absolute right-1.5 top-1.5 rounded bg-black/70 px-1.5 py-0.5 text-[10px] text-white">
            {card.remarks}
          </span>
        ) : null}
        {!card.playable ? (
          <span className="absolute bottom-1.5 left-1.5 rounded bg-zinc-800/90 px-1.5 py-0.5 text-[10px] text-zinc-300">
            {card.availabilityLabel || "暂不可播"}
          </span>
        ) : null}
        {busy ? (
          <div className="absolute inset-0 flex items-center justify-center bg-black/50 text-xs text-white">
            打开中…
          </div>
        ) : null}
      </div>
      <div className="mt-2 space-y-0.5 px-0.5">
        <h3 className="line-clamp-2 text-sm font-medium leading-snug">
          {card.title}
        </h3>
        <p className="truncate text-xs text-[var(--muted)]">
          {[card.year, card.genres[0]].filter(Boolean).join(" · ")}
        </p>
        {error ? (
          <p className="text-[10px] text-yellow-300">{error}</p>
        ) : null}
      </div>
    </button>
  );
}

export default function HomeShelves({ sections }: HomeShelvesProps) {
  if (!sections.length) {
    return (
      <p className="text-sm text-[var(--muted)]">推荐内容暂不可用</p>
    );
  }

  return (
    <div className="space-y-8">
      {sections.map((section) => (
        <section key={section.id} className="space-y-3">
          <div>
            <h2 className="text-lg font-semibold">{section.title}</h2>
            {section.subtitle ? (
              <p className="text-sm text-[var(--muted)]">{section.subtitle}</p>
            ) : null}
          </div>
          <div className="-mx-4 overflow-x-auto px-4 pb-1">
            <div className="flex w-max gap-3">
              {section.cards.map((card) => (
                <FeedCard key={card.id} card={card} />
              ))}
            </div>
          </div>
        </section>
      ))}
    </div>
  );
}
