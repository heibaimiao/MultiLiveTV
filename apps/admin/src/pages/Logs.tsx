import { useEffect, useState } from "react";
import { api, LogEntry } from "../api/client";

export default function Logs() {
  const [logs, setLogs] = useState<LogEntry[]>([]);

  async function load() {
    const res = await api.logs();
    setLogs([...res.logs].reverse());
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 5000);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-bold">请求日志</h2>
        <button onClick={load} className="px-3 py-1 rounded bg-slate-800">刷新</button>
      </div>
      <div className="overflow-x-auto max-h-[70vh]">
        <table className="w-full text-sm font-mono">
          <thead>
            <tr className="text-left text-slate-400 border-b border-slate-800 sticky top-0 bg-slate-950">
              <th className="p-2">时间</th>
              <th className="p-2">方法</th>
              <th className="p-2">路径</th>
              <th className="p-2">状态</th>
              <th className="p-2">耗时</th>
            </tr>
          </thead>
          <tbody>
            {logs.map((log, i) => (
              <tr key={i} className="border-b border-slate-900">
                <td className="p-2 whitespace-nowrap">{new Date(log.time).toLocaleTimeString()}</td>
                <td className="p-2">{log.method}</td>
                <td className="p-2">{log.path}</td>
                <td className={`p-2 ${log.status >= 400 ? "text-red-400" : "text-green-400"}`}>{log.status}</td>
                <td className="p-2">{log.latency}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
