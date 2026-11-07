export default function Loading() {
  return (
    <div aria-label="Loading workspace" className="animate-pulse space-y-6">
      <div className="h-9 w-3/4 rounded bg-muted" />
      <div className="h-4 w-1/2 rounded bg-muted" />
      <div className="grid gap-4 md:grid-cols-3">
        {[1, 2, 3].map((item) => (
          <div
            key={item}
            className="h-56 rounded-lg border border-border bg-muted"
          />
        ))}
      </div>
    </div>
  );
}
