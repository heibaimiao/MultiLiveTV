import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import "./globals.css";
import SearchBar from "@/components/SearchBar";

export const metadata: Metadata = {
  title: "MultiLiveTV - 点播影视",
  description: "MacCMS 采集 API 聚合点播网站",
  icons: {
    icon: [{ url: "/favicon.ico" }, { url: "/icon-192.png", sizes: "192x192" }],
    apple: [{ url: "/icon-192.png", sizes: "192x192" }],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body className="min-h-screen antialiased">
        <header className="sticky top-0 z-50 border-b border-[var(--border)] bg-[var(--background)]/90 backdrop-blur">
          <div className="mx-auto flex max-w-7xl flex-col gap-4 px-4 py-4 sm:flex-row sm:items-center sm:justify-between">
            <Link
              href="/"
              className="flex items-center gap-2.5 text-xl font-bold tracking-tight"
            >
              <Image
                src="/icon-192.png"
                alt=""
                width={32}
                height={32}
                className="h-8 w-8 rounded-lg"
                priority
              />
              <span>
                MultiLive<span className="text-[var(--accent)]">TV</span>
              </span>
            </Link>
            <SearchBar />
          </div>
        </header>
        <main className="mx-auto max-w-7xl px-4 py-8">{children}</main>
      </body>
    </html>
  );
}
