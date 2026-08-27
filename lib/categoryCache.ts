import { unstable_cache } from "next/cache";
import { fetchVodTypes } from "./maccms";
import { buildCategoryTree, type CategoryTree } from "./categoryTree";
import { getSourceById } from "./sources";

const EMPTY_TREE: CategoryTree = {
  all: [],
  primary: [],
  childrenByParent: {},
};

export function getCachedCategoryTree(sourceId: number): Promise<CategoryTree> {
  return unstable_cache(
    async () => {
      const source = getSourceById(sourceId);
      if (!source) return EMPTY_TREE;
      const types = await fetchVodTypes(source);
      return buildCategoryTree(types);
    },
    [`category-tree-v1-${sourceId}`],
    { revalidate: 300 }
  )();
}
