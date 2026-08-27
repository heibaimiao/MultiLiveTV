"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";

export default function SearchBar({ defaultValue = "" }: { defaultValue?: string }) {
  const router = useRouter();
  const [keyword, setKeyword] = useState(defaultValue);

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    const value = keyword.trim();
    if (!value) return;
    router.push(`/search?wd=${encodeURIComponent(value)}`);
  }

  return (
    <form onSubmit={handleSubmit} className="flex w-full max-w-xl gap-2">
      <input
        type="search"
        value={keyword}
        onChange={(e) => setKeyword(e.target.value)}
        placeholder="搜索影片..."
        className="flex-1 rounded-lg border border-[var(--border)] bg-[var(--card)] px-4 py-2.5 text-sm outline-none focus:border-[var(--accent)]"
      />
      <button
        type="submit"
        className="rounded-lg bg-[var(--accent)] px-5 py-2.5 text-sm font-medium text-white transition hover:bg-[var(--accent-hover)]"
      >
        搜索
      </button>
    </form>
  );
}
