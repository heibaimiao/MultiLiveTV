import type { VodType } from "./types";

export interface CategoryDef {
  typeId: number;
  label: string;
}

export interface CategoryTree {
  all: CategoryDef[];
  primary: CategoryDef[];
  childrenByParent: Record<number, CategoryDef[]>;
}

const TYPE_ALIASES: Record<string, string> = {
  日本剧: "日剧",
  韩国剧: "韩剧",
  泰国剧: "泰剧",
  台湾剧: "台剧",
  香港剧: "港剧",
  大陆剧: "国产剧",
  记录片: "纪录片",
  日本动漫: "日韩动漫",
  连续剧: "剧集",
  电影片: "电影",
  综艺片: "综艺",
  动漫片: "动漫",
};

const PARENT_NAMES = new Set(["电影", "剧集", "综艺", "动漫"]);

export function normalizeTypeName(typeName?: string): string {
  if (!typeName) return "";
  const cleaned = typeName.replace(/\[关\]/g, "").replace(/x$/i, "").trim();
  return TYPE_ALIASES[cleaned] ?? cleaned;
}

export function isTypeVisible(typeName: string): boolean {
  if (typeName.includes("[关]")) return false;
  if (/x$/i.test(typeName.trim())) return false;
  if (typeName.includes("伦理") || typeName.includes("倫理")) return false;
  return true;
}

export function filterVisibleTypes(types: VodType[]): VodType[] {
  return types.filter((type) => isTypeVisible(type.type_name));
}

function toDef(type: VodType): CategoryDef {
  return {
    typeId: type.type_id,
    label: normalizeTypeName(type.type_name),
  };
}

function isParentType(typeName: string): boolean {
  return PARENT_NAMES.has(normalizeTypeName(typeName));
}

export function getChildTypeIds(types: VodType[], parentId: number): number[] {
  const parent = types.find((type) => type.type_id === parentId);
  if (!parent || !isParentType(parent.type_name)) return [];

  const parentName = normalizeTypeName(parent.type_name);
  const visible = filterVisibleTypes(types).filter(
    (type) => type.type_id !== parentId && !isParentType(type.type_name)
  );

  const matchers: Record<string, (name: string) => boolean> = {
    电影: (name) =>
      (/片$/.test(name) || name === "纪录片") && !/动漫|动画/.test(name),
    剧集: (name) => /剧$/.test(name) && name !== "短剧",
    综艺: (name) => /综艺/.test(name),
    动漫: (name) => /动漫|动画片/.test(name),
  };

  const match = matchers[parentName];
  if (!match) return [];

  return visible
    .filter((type) => match(normalizeTypeName(type.type_name)))
    .map((type) => type.type_id);
}

export function buildCategoryTree(types: VodType[]): CategoryTree {
  const visible = filterVisibleTypes(types);
  const all = visible.map(toDef);
  const parents = visible.filter((type) => isParentType(type.type_name));
  const parentIds = new Set(parents.map((type) => type.type_id));

  const childrenByParent: Record<number, CategoryDef[]> = {};
  for (const parent of parents) {
    const childIds = getChildTypeIds(visible, parent.type_id);
    childrenByParent[parent.type_id] = childIds
      .map((id) => visible.find((type) => type.type_id === id))
      .filter((type): type is VodType => Boolean(type))
      .map(toDef);
  }

  const childIdSet = new Set(
    Object.values(childrenByParent)
      .flat()
      .map((category) => category.typeId)
  );

  const standalone = visible
    .filter(
      (type) =>
        !parentIds.has(type.type_id) && !childIdSet.has(type.type_id)
    )
    .map(toDef);

  return {
    all,
    primary: [...parents.map(toDef), ...standalone],
    childrenByParent,
  };
}

export function getParentTypeId(
  tree: CategoryTree,
  typeId: number | null
): number | null {
  if (typeId === null) return null;

  if (
    tree.childrenByParent[typeId]?.length &&
    tree.primary.some((item) => item.typeId === typeId)
  ) {
    return typeId;
  }

  for (const [parentId, children] of Object.entries(tree.childrenByParent)) {
    if (children.some((child) => child.typeId === typeId)) {
      return Number(parentId);
    }
  }

  if (tree.primary.some((item) => item.typeId === typeId)) {
    return typeId;
  }

  return null;
}

export function getCategoryLabel(
  tree: CategoryTree,
  typeId: number | null
): string {
  if (typeId === null) return "全部";
  return tree.all.find((item) => item.typeId === typeId)?.label ?? String(typeId);
}
