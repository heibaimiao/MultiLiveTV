import { NextResponse } from "next/server";
import { getPublicUnifiedCatalog } from "@/lib/unifiedCategories";

export async function GET() {
  return NextResponse.json(getPublicUnifiedCatalog());
}
