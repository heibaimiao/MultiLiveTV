import Link from "next/link";
import VodDetailClient from "@/components/VodDetailClient";
import { fetchMergedVodDetail } from "@/lib/vodMerge";
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
    const merged = await fetchMergedVodDetail(source, id);
    if (!merged) {
      return (
        <div className="space-y-4">
          <p className="text-[var(--muted)]">影片不存在</p>
          <Link href="/" className="text-[var(--accent)] hover:underline">
            返回首页
          </Link>
        </div>
      );
    }

    return (
      <VodDetailClient
        vod={merged.vod}
        playSources={merged.playSources}
        sourceId={merged.primarySourceId}
        sourceName={source.name}
        variants={merged.variants}
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
