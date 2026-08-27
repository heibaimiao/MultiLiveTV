export default function HomeLoading() {
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <div className="h-8 w-32 animate-pulse rounded bg-zinc-800" />
        <div className="h-4 w-48 animate-pulse rounded bg-zinc-800/70" />
      </div>
      <div className="flex gap-2 overflow-hidden">
        {Array.from({ length: 6 }).map((_, index) => (
          <div
            key={index}
            className="h-8 w-16 shrink-0 animate-pulse rounded-full bg-zinc-800"
          />
        ))}
      </div>
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6">
        {Array.from({ length: 12 }).map((_, index) => (
          <div
            key={index}
            className="animate-pulse overflow-hidden rounded-xl bg-[var(--card)]"
          >
            <div className="aspect-[2/3] bg-zinc-800" />
            <div className="space-y-2 p-3">
              <div className="h-4 rounded bg-zinc-800" />
              <div className="h-3 w-2/3 rounded bg-zinc-800/70" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
