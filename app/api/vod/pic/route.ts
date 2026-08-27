import { NextRequest, NextResponse } from "next/server";
import { fetchVodDetail } from "@/lib/maccms";
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
    const data = await fetchVodDetail(source, ids);
    const url = data.list?.[0]?.vod_pic ?? null;
    return NextResponse.json({ url });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Failed to fetch pic";
    return NextResponse.json({ error: message, url: null }, { status: 502 });
  }
}
