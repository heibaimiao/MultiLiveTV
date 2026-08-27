import { useEffect, useState } from "react";
import { api, SystemStatus, UserStats } from "../api/client";

export default function Dashboard() {
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [stats, setStats] = useState<UserStats | null>(null);
  const [message, setMessage] = useState("");

  useEffect(() => {
    api.systemStatus().then(setStatus).catch(() => {});
    api.userStats().then(setStats).catch(() => {});
  }, []);

  async function clearCache() {
    try {
      await api.clearCache();
      setMessage("缓存已清空");
      setStatus(await api.systemStatus());
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "失败");
    }
  }

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold">仪表盘</h2>
      {message && <p className="text-green-400">{message}</p>}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card title="运行时间" value={status?.uptime ?? "-"} />
        <Card title="资源站" value={`${status?.sources_live ?? 0} / ${status?.sources ?? 0}`} />
        <Card title="缓存条目" value={String(status?.cache_items ?? 0)} />
        <Card title="数据库" value={status?.db ?? "-"} />
        <Card title="用户总数" value={String(stats?.total_users ?? 0)} />
        <Card title="今日新增" value={String(stats?.today_new_users ?? 0)} />
        <Card title="收藏总数" value={String(stats?.total_favorites ?? 0)} />
      </div>
      <button onClick={clearCache} className="px-4 py-2 rounded bg-amber-600 hover:bg-amber-500">
        清空分类缓存
      </button>
    </div>
  );
}

function Card({ title, value }: { title: string; value: string }) {
  return (
    <div className="bg-slate-900 border border-slate-800 rounded-xl p-4">
      <p className="text-slate-400 text-sm">{title}</p>
      <p className="text-2xl font-semibold mt-1">{value}</p>
    </div>
  );
}
