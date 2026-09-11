import HomePageClient from "@/components/HomePageClient";
import { bpz5Configured, fetchHomeFeed } from "@/lib/bpz5";
import { getEnabledSources } from "@/lib/sources";
import {
  DEFAULT_HOME_SLUG,
  fetchUnifiedList,
  getPublicUnifiedCatalog,
  resolveHomeSlug,
} from "@/lib/unifiedCategories";
import { mergeIntoPool } from "@/lib/homeFeed";

export const dynamic = "force-dynamic";

interface HomePageProps {
  searchParams: Promise<{
    cat?: string;
    t?: string;
    category?: string;
  }>;
}

export default async function HomePage({ searchParams }: HomePageProps) {
  const params = await searchParams;
  const slug = resolveHomeSlug(params.cat ?? params.category ?? null);
  void params.t;

  const catalog = getPublicUnifiedCatalog();
  const sources = getEnabledSources();
  const feedConfigured = bpz5Configured();

  let pool: Awaited<ReturnType<typeof fetchUnifiedList>>["list"] = [];
  let pagecount = 1;
  let sourcesUsed: number[] = [];
  let feedSections: Awaited<ReturnType<typeof fetchHomeFeed>>["sections"] = [];
  let initialSlug: string | null = slug;

  if (feedConfigured && slug === null) {
    const feed = await fetchHomeFeed();
    feedSections = feed.sections;
    initialSlug = null;
    if (!feed.enabled) {
      // keep recommend tab selected; client shows empty/error until retry
      pool = [];
    }
  } else {
    const listSlug = slug ?? DEFAULT_HOME_SLUG;
    initialSlug = listSlug;
    try {
      const result = await fetchUnifiedList(listSlug, 1);
      pool = mergeIntoPool([], result.list, true);
      pagecount = result.pagecount;
      sourcesUsed = result.sourcesUsed;
    } catch {
      pool = [];
    }
  }

  return (
    <HomePageClient
      initialSlug={initialSlug}
      initialPool={pool}
      initialPageCount={pagecount}
      primary={catalog.primary}
      childrenByParent={catalog.childrenByParent}
      sourceCount={sources.length}
      sourcesUsed={sourcesUsed}
      feedEnabled={feedConfigured}
      initialFeedSections={feedSections}
    />
  );
}
