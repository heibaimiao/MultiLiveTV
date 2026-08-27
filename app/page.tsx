import HomePageClient from "@/components/HomePageClient";
import {
  fetchVodListByType,
  parseTypeId,
  parseLegacyCategory,
} from "@/lib/categories";
import { getCachedCategoryTree } from "@/lib/categoryCache";
import type { CategoryTree } from "@/lib/categoryTree";
import { getEnabledSources, getDefaultSource } from "@/lib/sources";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

interface HomePageProps {
  searchParams: Promise<{ t?: string; category?: string }>;
}

const EMPTY_TREE: CategoryTree = {
  all: [],
  primary: [],
  childrenByParent: {},
};

export default async function HomePage({ searchParams }: HomePageProps) {
  const params = await searchParams;

  if (params.category && !params.t) {
    const legacyId = parseLegacyCategory(params.category);
    redirect(legacyId ? `/?t=${legacyId}` : "/");
  }

  const typeId = parseTypeId(params.t);
  const sources = getEnabledSources();
  const defaultSource = getDefaultSource();

  let items: Awaited<ReturnType<typeof fetchVodListByType>>["list"] = [];
  let pageCount = 1;
  let categoryTree: CategoryTree = EMPTY_TREE;
  let activeSource = defaultSource;

  for (const source of sources) {
    try {
      const tree = await getCachedCategoryTree(source.id);
      const data = await fetchVodListByType(source, typeId, 1);
      if (tree.primary.length) {
        categoryTree = tree;
      }
      if (data.list?.length) {
        items = data.list;
        pageCount = data.pagecount ?? 1;
        activeSource = source;
        break;
      }
    } catch {
      continue;
    }
  }

  if (!categoryTree.primary.length) {
    try {
      categoryTree = await getCachedCategoryTree(activeSource.id);
    } catch {
      categoryTree = EMPTY_TREE;
    }
  }

  return (
    <HomePageClient
      initialTypeId={typeId}
      initialItems={items}
      initialPageCount={pageCount}
      categoryTree={categoryTree}
      sourceId={activeSource.id}
      sourceName={activeSource.name}
      sourceCount={sources.length}
    />
  );
}
