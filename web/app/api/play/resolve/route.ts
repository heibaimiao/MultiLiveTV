import { NextRequest, NextResponse } from "next/server";
import { bpz5Configured, normalizeTicket, resolveBpz5Ticket } from "@/lib/bpz5";
import { parsePlayAddress } from "@/lib/parser";
import { getSourceById } from "@/lib/sources";
import type { PlayResolveRequest } from "@/lib/types";

export async function POST(request: NextRequest) {
  let body: PlayResolveRequest;
  try {
    body = (await request.json()) as PlayResolveRequest;
  } catch {
    return NextResponse.json({ error: "invalid json body" }, { status: 400 });
  }

  const mode = body.mode || "direct";

  if (mode === "ticket") {
    const ticket = normalizeTicket(body.ticket, body.url);
    if (!ticket) {
      return NextResponse.json(
        { error: "ticket is required for ticket mode" },
        { status: 400 }
      );
    }
    if (!bpz5Configured()) {
      return NextResponse.json({ error: "ticket_not_enabled" }, { status: 501 });
    }
    try {
      const resolved = await resolveBpz5Ticket(ticket);
      return NextResponse.json({
        url: resolved.url,
        parsed: true,
        mode: "ticket",
        playFrom: body.playFrom || undefined,
        expiresAt: null,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Resolve failed";
      if (message === "ticket_not_enabled") {
        return NextResponse.json({ error: message }, { status: 501 });
      }
      return NextResponse.json({ error: message }, { status: 502 });
    }
  }

  if (mode !== "direct") {
    return NextResponse.json({ error: "unsupported_mode" }, { status: 400 });
  }

  if (!body.url) {
    return NextResponse.json(
      { error: "url is required for direct mode" },
      { status: 400 }
    );
  }

  const jx = body.jx !== false;
  if (!jx || !body.sourceId) {
    return NextResponse.json({
      url: body.url,
      parsed: false,
      mode: "direct",
      playFrom: body.playFrom || undefined,
      expiresAt: null,
    });
  }

  const source = getSourceById(body.sourceId);
  if (!source) {
    return NextResponse.json({ error: "Source not found" }, { status: 404 });
  }

  try {
    const result = await parsePlayAddress(source, body.url);
    return NextResponse.json({
      ...result,
      mode: result.mode || "direct",
      playFrom: body.playFrom || undefined,
      expiresAt: null,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Resolve failed";
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
