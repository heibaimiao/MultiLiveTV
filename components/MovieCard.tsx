"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { fetchAndCachePic, getCachedPic } from "@/lib/vodPicCache";
import { normalizeTypeName } from "@/lib/categories";
import type { VodItem } from "@/lib/types";

interface MovieCardProps {
  item: VodItem;
  sourceId: number;
  sourceName?: string;
}

export default function MovieCard({ item, sourceId, sourceName }: MovieCardProps) {
  const [pic, setPic] = useState("/placeholder.svg");

  useEffect(() => {
    let cancelled = false;

    async function loadPic() {
      if (item.vod_pic) {
        setPic(item.vod_pic);
        return;
      }

      const cached = getCachedPic(sourceId, item.vod_id);
      if (cached) {
        setPic(cached);
        return;
      }

      const url = await fetchAndCachePic(sourceId, item.vod_id);
      if (!cancelled && url) {
        setPic(url);
      }
    }

    loadPic();
    return () => {
      cancelled = true;
    };
  }, [item.vod_pic, item.vod_id, sourceId]);

  return (
    <Link
      href={`/vod/${item.vod_id}?source=${sourceId}`}
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
        {item.vod_remarks && (
          <span className="absolute right-2 top-2 rounded bg-black/70 px-2 py-0.5 text-xs text-white">
            {item.vod_remarks}
          </span>
        )}
      </div>
      <div className="p-3">
        <h3 className="line-clamp-2 text-sm font-medium">{item.vod_name}</h3>
        <p className="mt-1 text-xs text-[var(--muted)]">
          {[sourceName, item.type_name && normalizeTypeName(item.type_name), item.vod_year]
            .filter(Boolean)
            .join(" · ")}
        </p>
      </div>
    </Link>
  );
}
