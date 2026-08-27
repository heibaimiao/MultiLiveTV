import { useEffect, useState } from "react";
import { api, UserItem } from "../api/client";

export default function Users() {
  const [users, setUsers] = useState<UserItem[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState("");

  async function load(p = page) {
    try {
      const res = await api.listUsers(p);
      setUsers(res.users);
      setTotal(res.total);
      setPage(res.page);
    } catch (err) {
      setError(err instanceof Error ? err.message : "加载失败");
    }
  }

  useEffect(() => {
    load();
  }, []);

  return (
    <div className="space-y-4">
      <h2 className="text-2xl font-bold">用户管理</h2>
      {error && <p className="text-red-400">{error}</p>}
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-slate-400 border-b border-slate-800">
            <th className="p-2">邮箱</th>
            <th className="p-2">注册时间</th>
            <th className="p-2">收藏数</th>
            <th className="p-2">操作</th>
          </tr>
        </thead>
        <tbody>
          {users.map((u) => (
            <tr key={u.id} className="border-b border-slate-900">
              <td className="p-2">{u.email}</td>
              <td className="p-2">{new Date(u.created_at).toLocaleString()}</td>
              <td className="p-2">{u.favorite_count}</td>
              <td className="p-2">
                <button
                  className="text-red-400"
                  onClick={async () => {
                    if (!confirm(`删除用户 ${u.email}？`)) return;
                    await api.deleteUser(u.id);
                    await load();
                  }}
                >
                  删除
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="flex gap-2 items-center">
        <button disabled={page <= 1} onClick={() => load(page - 1)} className="px-3 py-1 rounded bg-slate-800 disabled:opacity-40">上一页</button>
        <span className="text-slate-400">第 {page} 页 / 共 {total} 人</span>
        <button disabled={users.length < 20} onClick={() => load(page + 1)} className="px-3 py-1 rounded bg-slate-800 disabled:opacity-40">下一页</button>
      </div>
    </div>
  );
}
