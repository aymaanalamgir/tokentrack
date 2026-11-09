import type { QueryClient } from "@tanstack/react-query";

export async function invalidateProjectViews(
  client: QueryClient,
  organizationId: string,
  userId: string,
) {
  await client.invalidateQueries({
    predicate: (query) => {
      const [organization, user, path] = query.queryKey;
      return (
        organization === organizationId &&
        user === userId &&
        typeof path === "string" &&
        (path.startsWith("projects") ||
          path.startsWith("users") ||
          path.startsWith("organizational-units") ||
          path.startsWith("organizations/") ||
          path === "me/overview")
      );
    },
  });
}
