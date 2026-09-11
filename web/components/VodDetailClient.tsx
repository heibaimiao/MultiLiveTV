"use client";

import dynamic from "next/dynamic";
import { useEffect, useMemo, useRef, useState } from "react";
import Image from "next/image";
import EpisodeList from "@/components/EpisodeList";
import SourceTabs from "@/components/SourceTabs";
import { formatSourceMetaLabel } from "@/lib/vodMerge";
import {
  nextPlayableIndexes,
  preferredPlayableIndex,
  sortPlaySources,
} from "@/lib/playLineWeights";
import type { PlaySource, VodItem, VodVariant } from "@/lib/types";
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
  variants?: VodVariant[];
  ticketEnabled?: boolean;
}

export default function VodDetailClient({
  vod,
  playSources,
  sourceId,
  sourceName,
  variants = [],
  ticketEnabled = false,
}: VodDetailClientProps) {
  const orderedSources = useMemo(
    () => sortPlaySources(playSources),
    [playSources]
  );
  const [sourceIndex, setSourceIndex] = useState(() =>
    preferredPlayableIndex(orderedSources, { ticketEnabled })
  );
  const [episodeIndex, setEpisodeIndex] = useState(0);
  const [playUrl, setPlayUrl] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  /** Auto path allows weight fallback; manual line pick does not. */
  const allowFallbackRef = useRef(true);

  useEffect(() => {
    allowFallbackRef.current = true;
    setSourceIndex(
      preferredPlayableIndex(orderedSources, { ticketEnabled, episodeIndex: 0 })
    );
    setEpisodeIndex(0);
  }, [orderedSources, ticketEnabled]);

  const currentSource = orderedSources[sourceIndex];
  const currentEpisode = currentSource?.episodes[episodeIndex];
  const parseSourceId = currentSource?.sourceId ?? sourceId;
  const sourceMeta =
    variants.length > 0
      ? formatSourceMetaLabel(
          {
            ...vod,
            variants,
            primarySourceId: sourceId,
          },
          3
        )
      : sourceName;

  const storageKey = useMemo(
    () =>
      `vod-progress-${parseSourceId}-${vod.vod_id}-${currentSource?.key ?? sourceIndex}-${episodeIndex}`,
    [parseSourceId, vod.vod_id, currentSource?.key, sourceIndex, episodeIndex]
  );

  useEffect(() => {
    if (vod.vod_pic) {
      setCachedPic(sourceId, vod.vod_id, vod.vod_pic);
    }
  }, [sourceId, vod.vod_id, vod.vod_pic]);

  useEffect(() => {
    if (!currentEpisode?.url && !currentSource?.ticket) {
      setPlayUrl("");
      return;
    }

    let cancelled = false;

    async function resolveOne(source: PlaySource, epIndex: number) {
      const episode = source.episodes[epIndex] ?? source.episodes[0];
      const episodeUrl = episode?.url || "";
      const isTicket =
        source.mode === "ticket" ||
        episodeUrl.startsWith("resolve://") ||
        Boolean(source.ticket);
      const res = await fetch("/api/play/resolve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode: isTicket ? "ticket" : "direct",
          sourceId: source.sourceId ?? sourceId,
          url: episodeUrl,
          jx: true,
          ticket: source.ticket || undefined,
          providerId: source.providerId,
          playFrom: source.playFrom,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "解析失败");
      return data.url as string;
    }

    async function resolveUrl() {
      setLoading(true);
      setError(null);

      try {
        if (!currentSource) throw new Error("无可用线路");
        const url = await resolveOne(currentSource, episodeIndex);
        if (!cancelled) setPlayUrl(url);
      } catch (err) {
        if (cancelled) return;
        if (allowFallbackRef.current && currentSource) {
          const fallbacks = nextPlayableIndexes(orderedSources, sourceIndex, {
            episodeIndex,
            ticketEnabled,
            maxTries: 3,
          });
          for (const nextIndex of fallbacks) {
            try {
              const next = orderedSources[nextIndex];
              const url = await resolveOne(next, episodeIndex);
              if (cancelled) return;
              setSourceIndex(nextIndex);
              setPlayUrl(url);
              setError(null);
              return;
            } catch {
              // try next
            }
          }
        }
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "播放地址获取失败");
          setPlayUrl(currentEpisode?.url || "");
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
  }, [
    currentEpisode?.url,
    currentSource,
    episodeIndex,
    orderedSources,
    parseSourceId,
    sourceId,
    sourceIndex,
    ticketEnabled,
  ]);

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
            {[sourceMeta, vod.vod_year, vod.vod_area, vod.type_name]
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

      {orderedSources.length > 0 && (
        <div className="space-y-4">
          <SourceTabs
            playSources={orderedSources}
            activeIndex={sourceIndex}
            onSelect={(index) => {
              allowFallbackRef.current = false;
              setSourceIndex(index);
              setEpisodeIndex(0);
            }}
          />
          <EpisodeList
            episodes={currentSource?.episodes ?? []}
            activeIndex={episodeIndex}
            onSelect={(index) => {
              allowFallbackRef.current = false;
              setEpisodeIndex(index);
            }}
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
        <VideoPlayer url={playUrl} storageKey={storageKey} />
      )}
    </div>
  );
}
