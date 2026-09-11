import { fetchVodList, fetchVodTypes } from "./maccms";
import {
  buildCategoryTree,
  filterVisibleTypes,
  getCategoryLabel,
  getChildTypeIds,
  normalizeTypeName,
  type CategoryDef,
  type CategoryTree,
} from "./categoryTree";
import { mergeVodItems, sortMergedByUpdatedDesc } from "./vodMerge";
import type { Source, VodItem, VodType } from "./types";

export type { CategoryDef, CategoryTree };
export {
  buildCategoryTree,
  getCategoryLabel,
  getParentTypeId,
  normalizeTypeName,
} from "./categoryTree";

export async function loadCategoryTree(source: Source): Promise<CategoryTree> {
  const types = await fetchVodTypes(source);
  return buildCategoryTree(types);
}

/** @deprecated 使用 loadCategoryTree */
export async function loadCategories(source: Source): Promise<CategoryDef[]> {
  const tree = await loadCategoryTree(source);
  return tree.all;
}

export function parseTypeId(value?: string | null): number | null {
  if (!value) return null;
  const id = Number(value);
  return Number.isFinite(id) && id > 0 ? id : null;
}

const LEGACY_CATEGORY_TYPE: Record<string, number> = {
  movie: 1,
  tv: 2,
  anime: 4,
  variety: 3,
  "drama-film": 10,
  action: 5,
  comedy: 6,
  romance: 7,
  scifi: 8,
  horror: 9,
  war: 11,
  guochanju: 12,
  hanju: 16,
  riju: 15,
  gangju: 13,
  taiju: 14,
  oumeiju: 17,
  haiwaiju: 18,
  guoman: 32,
  rihanman: 34,
  ouman: 35,
  cartoon: 23,
  short: 26,
  documentary: 22,
};

export function parseLegacyCategory(value?: string | null): number | null {
  if (!value || value === "all") return null;
  return LEGACY_CATEGORY_TYPE[value] ?? null;
}

function mergeListItems(source: Source, items: VodItem[]) {
  return sortMergedByUpdatedDesc(
    mergeVodItems(
      items.map((item) => ({
        ...item,
        sourceId: source.id,
        sourceName: source.name,
      }))
    )
  );
}

export async function fetchVodListByType(
  source: Source,
  typeId: number | null,
  page = 1,
  knownTypes?: VodType[]
) {
  if (typeId === null) {
    const data = await fetchVodList(source, page);
    return {
      ...data,
      list: mergeListItems(source, data.list ?? []),
    };
  }

  const direct = await fetchVodList(source, page, typeId);
  if (direct.list?.length || (direct.total ?? 0) > 0) {
    return {
      ...direct,
      list: mergeListItems(source, direct.list ?? []),
    };
  }

  const types = knownTypes ?? (await fetchVodTypes(source));
  const childIds = getChildTypeIds(types, typeId);
  if (!childIds.length) {
    return direct;
  }

  const results = await Promise.all(
    childIds.map((childId) => fetchVodList(source, page, childId))
  );

  const list = mergeListItems(
    source,
    results.flatMap((data) => data.list ?? [])
  );
  const pagecount = Math.max(...results.map((data) => data.pagecount ?? 1), 1);
  const total = results.reduce((sum, data) => sum + (data.total ?? 0), 0);

  return {
    code: 1,
    msg: "ok",
    page,
    pagecount,
    limit: String(list.length),
    total,
    list,
  };
}

// Re-export for MovieCard
export { filterVisibleTypes, isTypeVisible } from "./categoryTree";
