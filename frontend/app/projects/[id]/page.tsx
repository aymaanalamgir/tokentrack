import { ProjectDetail } from "@/components/project-explorer";
export default async function ProjectPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  return <ProjectDetail id={(await params).id} />;
}
