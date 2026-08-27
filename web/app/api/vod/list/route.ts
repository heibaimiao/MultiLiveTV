import { NextRequest, NextResponse } from "next/server";
import { fetchVodListByType, parseTypeId } from "@/lib/categories";
import { getSourceById, getEnabledSources, getDefaultSource } from "@/lib/sources";

export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const sourceIdParam = searchParams.get("sourceId");
  const page = Number(searchParams.get("pg") ?? "1");
  const typeId = parseTypeId(searchParams.get("t"));

  const preferred = sourceIdParam
    ? getSourceById(Number(sourceIdParam))
    : null;

  const sources = preferred
    ? [preferred]
    : getEnabledSources();

  if (!sources.length || (sourceIdParam && !preferred)) {
    return NextResponse.json({ error: "Source not found" }, { status: 404 });
  }

  let lastError: string | null = null;

  for (const source of sources) {
    if (!source || source.flag !== 0) continue;

    try {
      const data = await fetchVodListByType(source, typeId, page);
      if (data.list?.length) {
        return NextResponse.json({
          source: { id: source.id, name: source.name },
          typeId,
          ...data,
        });
      }
    } catch (error) {
      lastError =
        error instanceof Error ? error.message : "Failed to fetch list";
    }
  }

  const fallback = preferred ?? getDefaultSource();
  return NextResponse.json({
    source: { id: fallback.id, name: fallback.name },
    typeId,
    code: 1,
    msg: lastError ?? "ok",
    page,
    pagecount: 0,
    limit: "24",
    total: 0,
    list: [],
  });
}
