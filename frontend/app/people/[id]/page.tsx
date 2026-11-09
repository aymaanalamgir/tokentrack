import { ProfileExplorer } from "@/components/profile-explorer";
export default async function PersonPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  return <ProfileExplorer id={(await params).id} />;
}
