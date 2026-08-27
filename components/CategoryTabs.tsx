"use client";

import type { CategoryDef } from "@/lib/categoryTree";

interface CategoryTabsProps {
  primary: CategoryDef[];
  secondary: CategoryDef[];
  activeTypeId: number | null;
  activeParentId: number | null;
  pending?: boolean;
  onSelect: (typeId: number | null) => void;
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
  activeTypeId,
  activeParentId,
  pending = false,
  onSelect,
}: CategoryTabsProps) {
  const showSecondary = secondary.length > 0 && activeParentId !== null;

  return (
    <div className="space-y-3">
      <div className="-mx-4 overflow-x-auto px-4 pb-1">
        <div className="flex w-max min-w-full gap-2">
          <TabButton
            label="全部"
            active={activeTypeId === null}
            disabled={pending}
            onClick={() => onSelect(null)}
          />
          {primary.map((category) => (
            <TabButton
              key={category.typeId}
              label={category.label}
              active={
                activeTypeId === category.typeId ||
                activeParentId === category.typeId
              }
              disabled={pending}
              onClick={() => onSelect(category.typeId)}
            />
          ))}
        </div>
      </div>

      {showSecondary && (
        <div className="-mx-4 overflow-x-auto px-4 pb-1">
          <div className="flex w-max min-w-full gap-2">
            <TabButton
              label="全部"
              active={activeTypeId === activeParentId}
              disabled={pending}
              size="sm"
              onClick={() => onSelect(activeParentId)}
            />
            {secondary.map((category) => (
              <TabButton
                key={category.typeId}
                label={category.label}
                active={activeTypeId === category.typeId}
                disabled={pending}
                size="sm"
                onClick={() => onSelect(category.typeId)}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
