import Link from "next/link";
import VodDetailClient from "@/components/VodDetailClient";
import { fetchVodDetail } from "@/lib/maccms";
import { parsePlayUrl } from "@/lib/parser";
import { getSourceById } from "@/lib/sources";

export const dynamic = "force-dynamic";

interface VodPageProps {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ source?: string }>;
}

export default async function VodPage({ params, searchParams }: VodPageProps) {
  const { id } = await params;
  const { source: sourceParam } = await searchParams;
  const sourceId = Number(sourceParam);

  if (!sourceId) {
    return (
      <div className="space-y-4">
        <p className="text-[var(--muted)]">缺少 source 参数</p>
        <Link href="/" className="text-[var(--accent)] hover:underline">
          返回首页
        </Link>
      </div>
    );
  }

  const source = getSourceById(sourceId);
  if (!source) {
    return (
      <div className="space-y-4">
        <p className="text-[var(--muted)]">资源源不存在</p>
        <Link href="/" className="text-[var(--accent)] hover:underline">
          返回首页
        </Link>
      </div>
    );
  }

  try {
    const data = await fetchVodDetail(source, id);
    const vod = data.list?.[0];

    if (!vod) {
      return (
        <div className="space-y-4">
          <p className="text-[var(--muted)]">影片不存在</p>
          <Link href="/" className="text-[var(--accent)] hover:underline">
            返回首页
          </Link>
        </div>
      );
    }

    const playSources = parsePlayUrl(
      vod.vod_play_from ?? "",
      vod.vod_play_url ?? ""
    );

    return (
      <VodDetailClient
        vod={vod}
        playSources={playSources}
        sourceId={source.id}
        sourceName={source.name}
      />
    );
  } catch {
    return (
      <div className="space-y-4">
        <p className="text-[var(--muted)]">加载失败，资源源可能暂时不可用</p>
        <Link href="/" className="text-[var(--accent)] hover:underline">
          返回首页
        </Link>
      </div>
    );
  }
}
