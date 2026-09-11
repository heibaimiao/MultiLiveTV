import { MACCMS_MERGE_TIMEOUT_MS, searchVod } from "@/lib/maccms";
import { sourceWeight } from "@/lib/playLineWeights";
import { getEnabledSources } from "@/lib/sources";
import { isCompatibleVodMatch } from "@/lib/vodMerge";
import type { VodItem } from "@/lib/types";

export interface VodEntryResult {
  sourceId: number;
  vodId: string;
  vodName: string;
  vodPic?: string;
}

/**
 * Resolve a display title to a MacCMS detail entry (soft year match).
 * Searches higher-weight sources first with a short timeout.
 */
export async function resolveVodEntry(
  title: string,
  year?: string
): Promise<VodEntryResult | null> {
  const q = title.trim();
  if (!q) return null;

  const primary: Pick<VodItem, "vod_name" | "vod_year"> = {
    vod_name: q,
    vod_year: year?.trim() || "",
  };

  const sources = [...getEnabledSources()].sort(
    (a, b) => sourceWeight(b.id) - sourceWeight(a.id)
  );

  type Hit = VodEntryResult & { score: number };
  const hits: Hit[] = [];

  await Promise.all(
    sources.slice(0, 12).map(async (source) => {
      try {
        const data = await searchVod(source, q, 1, MACCMS_MERGE_TIMEOUT_MS);
        for (const item of data.list ?? []) {
          if (!isCompatibleVodMatch(primary, item)) continue;
          let score = sourceWeight(source.id);
          if (item.vod_pic) score += 50;
          if (
            primary.vod_year &&
            String(item.vod_year || "").includes(primary.vod_year)
          ) {
            score += 30;
          }
          hits.push({
            sourceId: source.id,
            vodId: String(item.vod_id),
            vodName: item.vod_name,
            vodPic: item.vod_pic,
            score,
          });
        }
      } catch {
        /* ignore */
      }
    })
  );

  if (!hits.length) return null;
  hits.sort((a, b) => b.score - a.score);
  const best = hits[0];
  return {
    sourceId: best.sourceId,
    vodId: best.vodId,
    vodName: best.vodName,
    vodPic: best.vodPic,
  };
}
