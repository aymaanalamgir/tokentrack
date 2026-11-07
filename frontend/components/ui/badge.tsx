import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";

export function Badge({ className, ...props }: ComponentProps<"span">) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded border border-border px-2 py-0.5 font-mono text-[10px] font-medium tracking-wide",
        className,
      )}
      {...props}
    />
  );
}
