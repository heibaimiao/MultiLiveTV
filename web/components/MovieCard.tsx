"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { fetchAndCachePic, getCachedPic } from "@/lib/vodPicCache";
import { normalizeTypeName } from "@/lib/categories";
import {
  getPrimaryVariant,
  formatSourceMetaLabel,
} from "@/lib/vodMerge";
import type { MergedVodItem, VodItem } from "@/lib/types";

interface MovieCardProps {
  item: VodItem | MergedVodItem;
  sourceId?: number;
  sourceName?: string;
}

function isMergedVodItem(item: VodItem | MergedVodItem): item is MergedVodItem {
  return "variants" in item && Array.isArray(item.variants);
}

export default function MovieCard({
  item,
  sourceId,
  sourceName,
}: MovieCardProps) {
  const [pic, setPic] = useState("/placeholder.svg");
  const merged = isMergedVodItem(item) ? item : null;
  const primaryVariant = merged ? getPrimaryVariant(merged) : null;
  const linkSourceId =
    primaryVariant?.sourceId ?? merged?.primarySourceId ?? sourceId ?? 0;
  const linkVodId = primaryVariant?.vodId ?? item.vod_id;
  const sourceCount = merged?.variants.length ?? (sourceName ? 1 : 0);
  const sourceLabel = merged
    ? formatSourceMetaLabel(merged, 2)
    : sourceName || "";
  const remarks = item.vod_remarks?.trim();

  useEffect(() => {
    let cancelled = false;

    async function loadPic() {
      if (item.vod_pic) {
        setPic(item.vod_pic);
        return;
      }

      const cached = getCachedPic(linkSourceId, linkVodId);
      if (cached) {
        setPic(cached);
        return;
      }

      const url = await fetchAndCachePic(linkSourceId, linkVodId);
      if (!cancelled && url) {
        setPic(url);
      }
    }

    loadPic();
    return () => {
      cancelled = true;
    };
  }, [item.vod_pic, linkSourceId, linkVodId]);

  return (
    <Link
      href={`/vod/${linkVodId}?source=${linkSourceId}`}
      className="group block overflow-hidden rounded-xl bg-[var(--card)] transition hover:bg-[var(--card-hover)]"
    >
      <div className="relative aspect-[2/3] w-full overflow-hidden bg-zinc-900">
        <Image
          src={pic}
          alt={item.vod_name}
          fill
          className="object-cover transition duration-300 group-hover:scale-105"
          sizes="(max-width: 768px) 33vw, 20vw"
          unoptimized
          onError={() => setPic("/placeholder.svg")}
        />
        {remarks && (
          <span className="absolute right-2 top-2 rounded bg-black/70 px-2 py-0.5 text-xs text-white">
            {remarks}
          </span>
        )}
        {sourceCount > 1 && (
          <span className="absolute left-2 top-2 rounded bg-[var(--accent)]/90 px-2 py-0.5 text-xs text-white">
            {sourceCount} 个源
          </span>
        )}
      </div>
      <div className="p-3">
        <h3 className="line-clamp-2 text-sm font-medium">{item.vod_name}</h3>
        <p className="mt-1 text-xs text-[var(--muted)]">
          {[
            remarks || sourceLabel,
            remarks && sourceLabel ? sourceLabel : null,
            item.type_name && normalizeTypeName(item.type_name),
            item.vod_year,
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
      </div>
    </Link>
  );
}
