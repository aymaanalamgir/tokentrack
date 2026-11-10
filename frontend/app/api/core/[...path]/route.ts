import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";
const cookieName = "tokentrack_demo_session";
const uuid = "[0-9a-f-]{36}";
const getPaths = new RegExp(
  `^(budgets|analytics|demo/identities|me(?:/access|/overview)?|organizations/${uuid}|organizational-units(?:/${uuid})?|users(?:/${uuid}(?:/reporting-context)?)?|projects(?:/eligible-users|/${uuid}(?:/eligible-users|/team-groups|/memberships)?)?)$`,
);

async function proxy(
  request: NextRequest,
  context: { params: Promise<{ path: string[] }> },
) {
  const path = (await context.params).path.join("/");
  const method = request.method;
  const permitted =
    method === "GET"
      ? getPaths.test(path)
      : method === "POST"
        ? path === "demo/sessions" ||
          path === "projects" ||
          /^budgets\/(?:transfers|funding|periods|ceilings|allocations|delegations(?:\/revoke)?)$/.test(path) ||
          new RegExp(
            `^projects/${uuid}/(?:memberships|transfer-ownership)$`,
          ).test(path)
        : method === "DELETE"
          ? path === "demo/session" ||
            new RegExp(`^projects/${uuid}/memberships/${uuid}$`).test(path)
          : method === "PATCH" &&
            new RegExp(`^projects/${uuid}(?:/memberships/${uuid})?$`).test(
              path,
            );
  const error = (code: string, message: string, status: number) =>
    NextResponse.json(
      { error: { code, message } },
      { status, headers: { "Cache-Control": "no-store, private" } },
    );
  if (!permitted) return error("not_found", "Unknown API route", 404);
  const publicOrigin = process.env.FRONTEND_ORIGIN ?? "http://localhost:3000";
  if (method !== "GET") {
    const origins = [publicOrigin];
    // Private Compose hostname for the development browser smoke runner only.
    if (process.env.NODE_ENV === "development")
      origins.push("http://frontend:3000");
    if (
      !origins.includes(request.headers.get("origin") ?? "") ||
      !request.headers.get("content-type")?.startsWith("application/json")
    ) {
      return error(
        "invalid_origin",
        "A same-origin JSON request is required",
        403,
      );
    }
  }
  try {
    const headers = new Headers({
      Accept: "application/json",
      Origin: publicOrigin,
    });
    const token = request.cookies.get(cookieName)?.value;
    if (token)
      headers.set("Cookie", `${cookieName}=${encodeURIComponent(token)}`);
    const body = method === "GET" ? undefined : await request.text();
    if (body && body.length > 16384)
      return error("invalid_request", "Request is too large", 413);
    if (body) headers.set("Content-Type", "application/json");
    const target = new URL(
      `/api/v1/${path}`,
      process.env.CORE_API_URL ?? "http://localhost:3001",
    );
    for (const [key, value] of request.nextUrl.searchParams) {
      if (
        [
          "month", "account_id", "as_of", "history_offset",
          "start", "end", "granularity", "organization_unit_id", "project_id", "user_id", "provider", "model", "tool", "audit_start", "audit_end",
          "q",
          "status",
          "department",
          "membership",
          "limit",
          "offset",
          "view",
          "managed",
          "state",
          "team",
          "include_members",
        ].includes(key)
      )
        target.searchParams.set(key, value);
    }
    const response = await fetch(target, {
      method,
      headers,
      body,
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(8000),
    });
    if (!response.headers.get("content-type")?.includes("application/json"))
      throw new Error("Invalid backend response");
    const output = NextResponse.json(await response.json(), {
      status: response.status,
      headers: { "Cache-Control": "no-store, private" },
    });
    for (const cookie of response.headers.getSetCookie())
      output.headers.append("Set-Cookie", cookie);
    return output;
  } catch {
    return error(
      "service_unavailable",
      "The Core API could not be reached. Try again shortly.",
      502,
    );
  }
}

export { proxy as GET, proxy as POST, proxy as PATCH, proxy as DELETE };
