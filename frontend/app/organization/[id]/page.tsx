import { OrganizationExplorer } from "@/components/organization-explorer";
export default async function UnitPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  return <OrganizationExplorer initialId={(await params).id} />;
}
