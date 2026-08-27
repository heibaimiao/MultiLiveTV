import { NextResponse } from "next/server";
import { getEnabledSources } from "@/lib/sources";

export async function GET() {
  const sources = getEnabledSources().map(({ id, name, url, flag, vip_only }) => ({
    id,
    name,
    url,
    flag,
    vip_only,
  }));
  return NextResponse.json({ sources });
}
