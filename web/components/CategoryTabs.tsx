"use client";

export interface SlugCategory {
  slug: string;
  label: string;
}

interface CategoryTabsProps {
  primary: SlugCategory[];
  secondary: SlugCategory[];
  activeSlug: string | null;
  activeParentSlug: string | null;
  pending?: boolean;
  /** When true, null slug means 推荐 feed; otherwise 全部 */
  feedMode?: boolean;
  onSelect: (slug: string | null) => void;
}

function TabButton({
  label,
  active,
  disabled,
  size = "md",
  onClick,
}: {
  label: string;
  active: boolean;
  disabled?: boolean;
  size?: "md" | "sm";
  onClick: () => void;
}) {
  const sizeClass = size === "sm" ? "px-3 py-1 text-xs" : "px-4 py-1.5 text-sm";

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className={`shrink-0 rounded-full transition ${sizeClass} disabled:cursor-wait ${
        active
          ? "bg-[var(--accent)] text-white"
          : "bg-[var(--card)] text-[var(--muted)] hover:text-white disabled:hover:text-[var(--muted)]"
      }`}
    >
      {label}
    </button>
  );
}

export default function CategoryTabs({
  primary,
  secondary,
  activeSlug,
  activeParentSlug,
  pending = false,
  feedMode = false,
  onSelect,
}: CategoryTabsProps) {
  const showSecondary = secondary.length > 0 && activeParentSlug !== null;

  return (
    <div className="space-y-3">
      <div className="-mx-4 overflow-x-auto px-4 pb-1">
        <div className="flex w-max min-w-full gap-2">
          <TabButton
            label={feedMode ? "推荐" : "全部"}
            active={activeSlug === null}
            disabled={pending}
            onClick={() => onSelect(null)}
          />
          {primary.map((category) => (
            <TabButton
              key={category.slug}
              label={category.label}
              active={
                activeSlug === category.slug ||
                activeParentSlug === category.slug
              }
              disabled={pending}
              onClick={() => onSelect(category.slug)}
            />
          ))}
        </div>
      </div>

      {showSecondary && (
        <div className="-mx-4 overflow-x-auto px-4 pb-1">
          <div className="flex w-max min-w-full gap-2">
            <TabButton
              label="全部"
              active={activeSlug === activeParentSlug}
              disabled={pending}
              size="sm"
              onClick={() => onSelect(activeParentSlug)}
            />
            {secondary.map((category) => (
              <TabButton
                key={category.slug}
                label={category.label}
                active={activeSlug === category.slug}
                disabled={pending}
                size="sm"
                onClick={() => onSelect(category.slug)}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
