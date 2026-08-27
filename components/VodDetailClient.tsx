"use client";

import dynamic from "next/dynamic";
import { useEffect, useMemo, useState } from "react";
import Image from "next/image";
import EpisodeList from "@/components/EpisodeList";
import SourceTabs from "@/components/SourceTabs";
import type { PlaySource, VodItem } from "@/lib/types";
import { setCachedPic } from "@/lib/vodPicCache";

const VideoPlayer = dynamic(() => import("@/components/VideoPlayer"), {
  ssr: false,
  loading: () => (
    <div className="flex aspect-video items-center justify-center rounded-xl bg-[var(--card)] text-[var(--muted)]">
      播放器加载中...
    </div>
  ),
});

interface VodDetailClientProps {
  vod: VodItem;
  playSources: PlaySource[];
  sourceId: number;
  sourceName: string;
}

export default function VodDetailClient({
  vod,
  playSources,
  sourceId,
  sourceName,
}: VodDetailClientProps) {
  const [sourceIndex, setSourceIndex] = useState(0);
  const [episodeIndex, setEpisodeIndex] = useState(0);
  const [playUrl, setPlayUrl] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const currentSource = playSources[sourceIndex];
  const currentEpisode = currentSource?.episodes[episodeIndex];

  const storageKey = useMemo(
    () => `vod-progress-${sourceId}-${vod.vod_id}-${sourceIndex}-${episodeIndex}`,
    [sourceId, vod.vod_id, sourceIndex, episodeIndex]
  );

  useEffect(() => {
    if (vod.vod_pic) {
      setCachedPic(sourceId, vod.vod_id, vod.vod_pic);
    }
  }, [sourceId, vod.vod_id, vod.vod_pic]);

  useEffect(() => {
    if (!currentEpisode?.url) {
      setPlayUrl("");
      return;
    }

    let cancelled = false;

    async function resolveUrl() {
      setLoading(true);
      setError(null);

      try {
        const res = await fetch(
          `/api/play/parse?sourceId=${sourceId}&url=${encodeURIComponent(currentEpisode.url)}`
        );
        const data = await res.json();
        if (!res.ok) throw new Error(data.error ?? "解析失败");
        if (!cancelled) setPlayUrl(data.url);
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "播放地址获取失败");
          setPlayUrl(currentEpisode.url);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    resolveUrl();
    return () => {
      cancelled = true;
      setPlayUrl("");
      setLoading(false);
    };
  }, [currentEpisode?.url, sourceId]);

  return (
    <div className="space-y-6">
      <div className="grid gap-6 lg:grid-cols-[240px_1fr]">
        <div className="relative mx-auto aspect-[2/3] w-full max-w-[240px] overflow-hidden rounded-xl bg-zinc-900">
          {vod.vod_pic && (
            <Image
              src={vod.vod_pic}
              alt={vod.vod_name}
              fill
              className="object-cover"
              unoptimized
            />
          )}
        </div>
        <div className="space-y-3">
          <h1 className="text-2xl font-bold">{vod.vod_name}</h1>
          <p className="text-sm text-[var(--muted)]">
            {[sourceName, vod.vod_year, vod.vod_area, vod.type_name]
              .filter(Boolean)
              .join(" · ")}
          </p>
          {vod.vod_remarks && (
            <span className="inline-block rounded bg-[var(--card)] px-3 py-1 text-sm">
              {vod.vod_remarks}
            </span>
          )}
          <p className="text-sm leading-relaxed text-zinc-300">
            {vod.vod_content?.replace(/<[^>]+>/g, "") ||
              vod.vod_blurb ||
              "暂无简介"}
          </p>
        </div>
      </div>

      {playSources.length > 0 && (
        <div className="space-y-4">
          <SourceTabs
            playSources={playSources}
            activeIndex={sourceIndex}
            onSelect={(index) => {
              setSourceIndex(index);
              setEpisodeIndex(0);
            }}
          />
          <EpisodeList
            episodes={currentSource?.episodes ?? []}
            activeIndex={episodeIndex}
            onSelect={setEpisodeIndex}
          />
        </div>
      )}

      {loading && (
        <div className="rounded-xl bg-[var(--card)] p-8 text-center text-[var(--muted)]">
          正在解析播放地址...
        </div>
      )}

      {error && (
        <div className="rounded-xl border border-yellow-500/30 bg-yellow-500/10 p-4 text-sm text-yellow-200">
          {error}，已尝试使用原始地址播放
        </div>
      )}

      {playUrl && !loading && (
        <VideoPlayer
          url={playUrl}
          title={vod.vod_name}
          storageKey={storageKey}
        />
      )}
    </div>
  );
}
