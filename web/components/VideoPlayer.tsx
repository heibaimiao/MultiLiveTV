"use client";

import { useCallback, useEffect, useRef } from "react";
import { usePathname } from "next/navigation";
import Artplayer from "artplayer";
import Hls from "hls.js";

interface VideoPlayerProps {
  url: string;
  title?: string;
  storageKey?: string;
}

export default function VideoPlayer({ url, storageKey }: VideoPlayerProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<Artplayer | null>(null);
  const hlsRef = useRef<Hls | null>(null);
  const pathname = usePathname();

  const destroyPlayer = useCallback(() => {
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }

    const player = playerRef.current;
    if (!player) return;

    try {
      const video = player.video as HTMLVideoElement | undefined;
      if (video) {
        video.pause();
        video.removeAttribute("src");
        video.load();
      }
      player.destroy(true);
    } catch {
      // ignore cleanup errors
    }

    playerRef.current = null;
  }, []);

  useEffect(() => {
    if (!containerRef.current || !url) return;

    const savedTime = storageKey
      ? Number(localStorage.getItem(storageKey) ?? "0")
      : 0;

    const art = new Artplayer({
      container: containerRef.current,
      url,
      autoplay: true,
      autoSize: true,
      pip: true,
      fullscreen: true,
      fullscreenWeb: true,
      setting: true,
      playbackRate: true,
      aspectRatio: true,
      theme: "#6366f1",
      customType: {
        m3u8(video, videoUrl) {
          if (hlsRef.current) {
            hlsRef.current.destroy();
            hlsRef.current = null;
          }

          if (Hls.isSupported()) {
            const hls = new Hls();
            hls.loadSource(videoUrl);
            hls.attachMedia(video);
            hlsRef.current = hls;
          } else if (video.canPlayType("application/vnd.apple.mpegurl")) {
            video.src = videoUrl;
          }
        },
      },
    });

    art.on("video:timeupdate", () => {
      if (storageKey && art.currentTime > 0) {
        localStorage.setItem(storageKey, String(Math.floor(art.currentTime)));
      }
    });

    art.on("ready", () => {
      if (savedTime > 0 && savedTime < art.duration - 10) {
        art.currentTime = savedTime;
      }
    });

    playerRef.current = art;

    return () => {
      destroyPlayer();
    };
  }, [url, storageKey, destroyPlayer]);

  useEffect(() => {
    if (!pathname.startsWith("/vod/")) {
      destroyPlayer();
    }
  }, [pathname, destroyPlayer]);

  useEffect(() => {
    const handlePageHide = () => destroyPlayer();
    window.addEventListener("pagehide", handlePageHide);
    return () => window.removeEventListener("pagehide", handlePageHide);
  }, [destroyPlayer]);

  return (
    <div className="overflow-hidden rounded-xl bg-black">
      <div ref={containerRef} className="aspect-video w-full" />
    </div>
  );
}
