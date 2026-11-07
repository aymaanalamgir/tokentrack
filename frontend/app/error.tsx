"use client";
import { CircleAlert } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <div
      role="alert"
      className="rounded-lg border border-border bg-surface p-8"
    >
      <CircleAlert className="text-danger" />
      <h1 className="mt-4 text-lg">The workspace could not load.</h1>
      <p className="my-3 text-sm text-muted-foreground">
        Try loading the workspace again.
      </p>
      <Button onClick={reset}>Try again</Button>
    </div>
  );
}
