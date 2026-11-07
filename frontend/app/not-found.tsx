import Link from "next/link";
import { Button } from "@/components/ui/button";

export default function NotFound() {
  return (
    <div className="rounded-lg border border-border bg-surface p-8">
      <p className="font-mono text-xs text-muted-foreground">404 / NOT FOUND</p>
      <h1 className="my-4 text-xl">
        This page isn’t part of the workspace yet.
      </h1>
      <Button asChild>
        <Link href="/">Back to overview</Link>
      </Button>
    </div>
  );
}
