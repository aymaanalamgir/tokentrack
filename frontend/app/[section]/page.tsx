import { notFound } from "next/navigation";
import { PlannedWorkspace } from "@/components/planned-workspace";
export default async function FuturePage({
  params,
}: {
  params: Promise<{ section: string }>;
}) {
  const { section } = await params;
  if (!["analytics", "budgets", "requests", "settings"].includes(section))
    notFound();
  return <PlannedWorkspace section={section} />;
}
