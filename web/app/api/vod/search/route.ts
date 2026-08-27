import { NextRequest, NextResponse } from "next/server";
import { searchVod } from "@/lib/maccms";
import { getEnabledSources, getSourceById } from "@/lib/sources";
import { mergeVodItems } from "@/lib/vodMerge";

export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const keyword = searchParams.get("wd")?.trim();
  const sourceId = searchParams.get("sourceId");
  const page = Number(searchParams.get("pg") ?? "1");

  if (!keyword) {
    return NextResponse.json({ error: "wd is required" }, { status: 400 });
  }

  const sources = sourceId
    ? [getSourceById(Number(sourceId))].filter(Boolean)
    : getEnabledSources();

  if (sources.length === 0) {
    return NextResponse.json({ error: "No sources available" }, { status: 404 });
  }

  const results = await Promise.allSettled(
    sources.map(async (source) => {
      const data = await searchVod(source!, keyword, page);
      return (data.list ?? []).map((item) => ({
        ...item,
        sourceId: source!.id,
        sourceName: source!.name,
      }));
    })
  );

  const rawList = results.flatMap((result) =>
    result.status === "fulfilled" ? result.value : []
  );
  const list = mergeVodItems(rawList);

  return NextResponse.json({
    keyword,
    merged: true,
    total: list.length,
    list,
  });
}
