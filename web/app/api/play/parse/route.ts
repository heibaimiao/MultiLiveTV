import { NextRequest, NextResponse } from "next/server";
import { parsePlayAddress } from "@/lib/parser";
import { getSourceById } from "@/lib/sources";

export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl;
  const sourceId = searchParams.get("sourceId");
  const url = searchParams.get("url");

  if (!sourceId || !url) {
    return NextResponse.json(
      { error: "sourceId and url are required" },
      { status: 400 }
    );
  }

  const source = getSourceById(Number(sourceId));
  if (!source) {
    return NextResponse.json({ error: "Source not found" }, { status: 404 });
  }

  try {
    const result = await parsePlayAddress(source, url);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Parse failed";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
