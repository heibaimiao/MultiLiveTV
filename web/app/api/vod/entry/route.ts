import { NextRequest, NextResponse } from "next/server";
import { resolveVodEntry } from "@/lib/vodEntry";

export async function GET(request: NextRequest) {
  const title = request.nextUrl.searchParams.get("title")?.trim() || "";
  const year = request.nextUrl.searchParams.get("year")?.trim() || "";

  if (!title) {
    return NextResponse.json({ error: "title is required" }, { status: 400 });
  }

  try {
    const entry = await resolveVodEntry(title, year || undefined);
    if (!entry) {
      return NextResponse.json({ error: "Vod not found" }, { status: 404 });
    }
    return NextResponse.json(entry);
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to resolve entry";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
