import { NextResponse } from "next/server";
import { fetchHomeFeed } from "@/lib/bpz5";

export async function GET() {
  const feed = await fetchHomeFeed();
  return NextResponse.json(feed);
}
