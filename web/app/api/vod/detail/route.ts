import { NextRequest, NextResponse } from "next/server";
import { fetchMergedVodDetail } from "@/lib/vodMerge";
import { getSourceById } from "@/lib/sources";

export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const sourceId = searchParams.get("sourceId");
  const ids = searchParams.get("ids");

  if (!sourceId || !ids) {
    return NextResponse.json(
      { error: "sourceId and ids are required" },
      { status: 400 }
    );
  }

  const source = getSourceById(Number(sourceId));
  if (!source || source.flag !== 0) {
    return NextResponse.json({ error: "Source not found" }, { status: 404 });
  }

  try {
    const merged = await fetchMergedVodDetail(source, ids);
    if (!merged) {
      return NextResponse.json({ error: "Vod not found" }, { status: 404 });
    }

    return NextResponse.json({
      source: { id: source.id, name: source.name },
      vod: merged.vod,
      playSources: merged.playSources,
      variants: merged.variants,
      merged: true,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to fetch detail";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
