import { NavLink, Outlet } from "react-router-dom";
import { clearToken } from "../api/client";

const links = [
  { to: "/", label: "仪表盘" },
  { to: "/sources", label: "资源站" },
  { to: "/users", label: "用户" },
  { to: "/logs", label: "日志" },
];

export default function Layout() {
  return (
    <div className="flex min-h-screen">
      <aside className="w-56 bg-slate-900 border-r border-slate-800 p-4 flex flex-col gap-2">
        <h1 className="text-lg font-bold mb-4">MultiLiveTV</h1>
        {links.map((link) => (
          <NavLink
            key={link.to}
            to={link.to}
            end={link.to === "/"}
            className={({ isActive }) =>
              `px-3 py-2 rounded-lg ${isActive ? "bg-slate-700" : "hover:bg-slate-800"}`
            }
          >
            {link.label}
          </NavLink>
        ))}
        <button
          className="mt-auto text-left px-3 py-2 rounded-lg text-red-400 hover:bg-slate-800"
          onClick={() => {
            clearToken();
            window.location.href = "/login";
          }}
        >
          退出
        </button>
      </aside>
      <main className="flex-1 p-6 overflow-auto">
        <Outlet />
      </main>
    </div>
  );
}
