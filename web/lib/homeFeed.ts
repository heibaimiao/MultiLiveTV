import { buildVodMergeKey, mergeVodItems, sortMergedByUpdatedDesc } from "./vodMerge";
import type { MergeableVodItem, MergedVodItem } from "./types";

export const HOME_FETCH_SIZE = 50;
export const HOME_INITIAL_DISPLAY = 30;
export const HOME_SCROLL_LOAD_SIZE = 20;

function isMergedVodItem(
  item: MergeableVodItem | MergedVodItem
): item is MergedVodItem {
  return "variants" in item && Array.isArray(item.variants);
}

export function flattenForMerge(
  items: Array<MergedVodItem | MergeableVodItem>,
  fallbackSourceId: number,
  fallbackSourceName: string
): MergeableVodItem[] {
  return items.flatMap((item) => {
    if (isMergedVodItem(item) && item.variants.length > 0) {
      return item.variants.map((variant) => ({
        ...item,
        vod_id: variant.vodId,
        sourceId: variant.sourceId,
        sourceName: variant.sourceName,
      }));
    }

    return [
      {
        ...item,
        sourceId:
          (!isMergedVodItem(item) ? item.sourceId : item.primarySourceId) ??
          fallbackSourceId,
        sourceName:
          (!isMergedVodItem(item)
            ? item.sourceName
            : item.variants[0]?.sourceName) ?? fallbackSourceName,
      },
    ];
  });
}

export function mergeIntoPool(
  pool: MergedVodItem[],
  incoming: MergeableVodItem[],
  isFirstBatch: boolean
): MergedVodItem[] {
  if (!incoming.length && !pool.length) return [];

  const fallbackSourceId = incoming[0]?.sourceId ?? pool[0]?.primarySourceId ?? 0;
  const fallbackSourceName =
    incoming[0]?.sourceName ?? pool[0]?.variants[0]?.sourceName ?? "";

  const merged = sortMergedByUpdatedDesc(
    mergeVodItems([
      ...flattenForMerge(pool, fallbackSourceId, fallbackSourceName),
      ...incoming,
    ])
  );

  if (isFirstBatch) {
    return merged.slice(0, HOME_FETCH_SIZE);
  }

  const existingKeys = new Set(pool.map((item) => buildVodMergeKey(item)));
  const newcomers = merged.filter(
    (item) => !existingKeys.has(buildVodMergeKey(item))
  );

  return sortMergedByUpdatedDesc([
    ...pool,
    ...newcomers.slice(0, HOME_FETCH_SIZE),
  ]);
}

export function getVisibleItems(
  pool: MergedVodItem[],
  displayCount: number
): MergedVodItem[] {
  return pool.slice(0, Math.min(displayCount, pool.length));
}

export function getInitialDisplayCount(poolLength: number): number {
  return Math.min(HOME_INITIAL_DISPLAY, poolLength);
}

export function getNextDisplayCount(current: number, poolLength: number): number {
  return Math.min(current + HOME_SCROLL_LOAD_SIZE, poolLength);
}

export function canLoadMoreFromPool(
  displayCount: number,
  poolLength: number,
  apiPage: number,
  pageCount: number
): boolean {
  return displayCount < poolLength || apiPage < pageCount;
}
