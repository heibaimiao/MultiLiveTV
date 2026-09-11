import catalogJson from "@/config/unified-categories.json";
import { fetchVodListByType } from "@/lib/categories";
import { mergeVodItems, sortMergedByUpdatedDesc } from "@/lib/vodMerge";
import { getEnabledSources, getSourceById } from "@/lib/sources";
import { sourceWeight } from "@/lib/playLineWeights";
import type { MergeableVodItem, MergedVodItem } from "@/lib/types";

export interface UnifiedCategoryNode {
  slug: string;
  label: string;
  sources: Record<string, number>;
  children?: UnifiedCategoryNode[];
}

export interface UnifiedCatalog {
  version: number;
  generated_at?: string;
  aliases?: Record<string, string>;
  defaultSlug: string;
  tree: UnifiedCategoryNode[];
}

export interface SlugCategory {
  slug: string;
  label: string;
}

const catalog = catalogJson as UnifiedCatalog;
const MAX_FANOUT = 8;

export const DEFAULT_HOME_SLUG = catalog.defaultSlug || "movie";

export function getUnifiedCatalog(): UnifiedCatalog {
  return catalog;
}

export function getPublicUnifiedCatalog() {
  const primary: SlugCategory[] = catalog.tree.map((node) => ({
    slug: node.slug,
    label: node.label,
  }));
  const childrenByParent: Record<string, SlugCategory[]> = {};
  for (const node of catalog.tree) {
    childrenByParent[node.slug] = (node.children ?? []).map((child) => ({
      slug: child.slug,
      label: child.label,
    }));
  }

  return {
    version: catalog.version,
    defaultSlug: DEFAULT_HOME_SLUG,
    primary,
    childrenByParent,
    tree: catalog.tree.map((node) => ({
      slug: node.slug,
      label: node.label,
      children: (node.children ?? []).map((child) => ({
        slug: child.slug,
        label: child.label,
      })),
    })),
  };
}

export function findUnifiedCategory(
  slug: string | null | undefined
): UnifiedCategoryNode | null {
  if (!slug) return null;
  for (const node of catalog.tree) {
    if (node.slug === slug) return node;
    for (const child of node.children ?? []) {
      if (child.slug === slug) return child;
    }
  }
  return null;
}

export function getParentSlug(slug: string | null | undefined): string | null {
  if (!slug) return null;
  for (const node of catalog.tree) {
    if (node.slug === slug) return node.slug;
    for (const child of node.children ?? []) {
      if (child.slug === slug) return node.slug;
    }
  }
  return null;
}

export function getCategoryLabelBySlug(slug: string | null | undefined): string {
  if (!slug) return "全部";
  return findUnifiedCategory(slug)?.label ?? slug;
}

/** 解析首页 `?cat=`；未知 slug 回落默认电影；`all` / 空 → null（全部） */
export function resolveHomeSlug(
  raw: string | null | undefined
): string | null {
  if (!raw || raw === "all") return null;
  if (findUnifiedCategory(raw)) return raw;
  return DEFAULT_HOME_SLUG;
}

export interface UnifiedListResult {
  cat: string;
  label: string;
  sourcesUsed: number[];
  sourcesFailed: number[];
  page: number;
  pagecount: number;
  total: number;
  list: MergedVodItem[];
}

export async function fetchUnifiedList(
  slug: string,
  page = 1
): Promise<UnifiedListResult> {
  const node = findUnifiedCategory(slug);
  if (!node) {
    throw new Error(`Category not found: ${slug}`);
  }

  const enabled = getEnabledSources();
  const enabledIds = new Set(enabled.map((s) => s.id));
  const mappings = Object.entries(node.sources)
    .map(([sid, tid]) => ({ sourceId: Number(sid), typeId: tid }))
    .filter((m) => enabledIds.has(m.sourceId))
    .sort((a, b) => sourceWeight(b.sourceId) - sourceWeight(a.sourceId));

  const queue = mappings.slice();
  const results: Array<{
    sourceId: number;
    items: MergeableVodItem[];
    total: number;
    pagecount: number;
    ok: boolean;
  }> = [];

  async function worker() {
    while (queue.length) {
      const mapping = queue.shift();
      if (!mapping) break;
      const source = getSourceById(mapping.sourceId);
      if (!source) {
        results.push({
          sourceId: mapping.sourceId,
          items: [],
          total: 0,
          pagecount: 0,
          ok: false,
        });
        continue;
      }
      try {
        const data = await fetchVodListByType(source, mapping.typeId, page);
        const items = (data.list ?? []).map((item) => ({
          ...item,
          sourceId: source.id,
          sourceName: source.name,
        }));
        results.push({
          sourceId: source.id,
          items,
          total: data.total ?? 0,
          pagecount: data.pagecount ?? 1,
          ok: items.length > 0,
        });
      } catch {
        results.push({
          sourceId: mapping.sourceId,
          items: [],
          total: 0,
          pagecount: 0,
          ok: false,
        });
      }
    }
  }

  await Promise.all(
    Array.from(
      { length: Math.min(MAX_FANOUT, Math.max(queue.length, 1)) },
      () => worker()
    )
  );

  const used = results.filter((r) => r.ok).map((r) => r.sourceId);
  const failed = results.filter((r) => !r.ok).map((r) => r.sourceId);
  const merged = sortMergedByUpdatedDesc(
    mergeVodItems(results.flatMap((r) => r.items))
  );
  const pagecount = Math.max(1, ...results.map((r) => r.pagecount || 1));
  const total = results.reduce((sum, r) => sum + (r.total || 0), 0);

  return {
    cat: slug,
    label: node.label,
    sourcesUsed: used,
    sourcesFailed: failed,
    page,
    pagecount,
    total,
    list: merged,
  };
}
