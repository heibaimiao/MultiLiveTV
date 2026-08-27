import { FormEvent, useEffect, useState } from "react";
import { api, Source } from "../api/client";

const empty: Source = { id: 0, name: "", url: "", flag: 0, jx_url: "", vip_only: false };

export default function Sources() {
  const [sources, setSources] = useState<Source[]>([]);
  const [form, setForm] = useState<Source>(empty);
  const [editing, setEditing] = useState<number | null>(null);
  const [testResult, setTestResult] = useState<Record<number, string>>({});
  const [error, setError] = useState("");

  async function load() {
    const res = await api.listSources();
    setSources(res.sources);
  }

  useEffect(() => {
    load().catch((e) => setError(e.message));
  }, []);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    try {
      if (editing) {
        await api.updateSource(editing, form);
      } else {
        await api.createSource(form);
      }
      setForm(empty);
      setEditing(null);
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "保存失败");
    }
  }

  async function onTest(id: number) {
    try {
      const res = await api.testSource(id);
      setTestResult((prev) => ({
        ...prev,
        [id]: res.ok ? `OK (${res.latency})` : `失败: ${res.error}`,
      }));
    } catch (err) {
      setTestResult((prev) => ({
        ...prev,
        [id]: err instanceof Error ? err.message : "失败",
      }));
    }
  }

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-bold">资源站管理</h2>
      {error && <p className="text-red-400">{error}</p>}

      <form onSubmit={onSubmit} className="grid grid-cols-1 md:grid-cols-3 gap-3 bg-slate-900 border border-slate-800 rounded-xl p-4">
        <input className="px-3 py-2 rounded bg-slate-800 border border-slate-700" placeholder="ID" type="number" value={form.id || ""} disabled={!!editing}
          onChange={(e) => setForm({ ...form, id: Number(e.target.value) })} />
        <input className="px-3 py-2 rounded bg-slate-800 border border-slate-700" placeholder="名称" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
        <input className="px-3 py-2 rounded bg-slate-800 border border-slate-700 md:col-span-3" placeholder="URL" value={form.url} onChange={(e) => setForm({ ...form, url: e.target.value })} />
        <input className="px-3 py-2 rounded bg-slate-800 border border-slate-700 md:col-span-2" placeholder="jx_url" value={form.jx_url || ""} onChange={(e) => setForm({ ...form, jx_url: e.target.value })} />
        <input className="px-3 py-2 rounded bg-slate-800 border border-slate-700" placeholder="flag (0=启用)" type="number" value={form.flag} onChange={(e) => setForm({ ...form, flag: Number(e.target.value) })} />
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={!!form.vip_only} onChange={(e) => setForm({ ...form, vip_only: e.target.checked })} />
          VIP only
        </label>
        <button type="submit" className="px-4 py-2 rounded bg-blue-600 hover:bg-blue-500 md:col-span-3">
          {editing ? "更新" : "新增"}
        </button>
      </form>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-slate-400 border-b border-slate-800">
              <th className="p-2">ID</th>
              <th className="p-2">名称</th>
              <th className="p-2">URL</th>
              <th className="p-2">Flag</th>
              <th className="p-2">操作</th>
            </tr>
          </thead>
          <tbody>
            {sources.map((s) => (
              <tr key={s.id} className="border-b border-slate-900">
                <td className="p-2">{s.id}</td>
                <td className="p-2">{s.name}</td>
                <td className="p-2 max-w-xs truncate">{s.url}</td>
                <td className="p-2">{s.flag}</td>
                <td className="p-2 space-x-2">
                  <button className="text-blue-400" onClick={() => { setEditing(s.id); setForm(s); }}>编辑</button>
                  <button className="text-amber-400" onClick={() => onTest(s.id)}>测试</button>
                  <button className="text-red-400" onClick={async () => { await api.deleteSource(s.id); await load(); }}>删除</button>
                  {testResult[s.id] && <span className="text-slate-400">{testResult[s.id]}</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
