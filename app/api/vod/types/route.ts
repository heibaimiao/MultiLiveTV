import { NextRequest, NextResponse } from "next/server";
import { loadCategories } from "@/lib/categories";
import { getSourceById, getDefaultSource } from "@/lib/sources";

export async function GET(request: NextRequest) {
  const sourceId = request.nextUrl.searchParams.get("sourceId");
  const source = sourceId
    ? getSourceById(Number(sourceId))
    : getDefaultSource();

  if (!source || source.flag !== 0) {
    return NextResponse.json({ error: "Source not found" }, { status: 404 });
  }

  try {
    const categories = await loadCategories(source);
    return NextResponse.json({
      source: { id: source.id, name: source.name },
      categories,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Failed to fetch types";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
