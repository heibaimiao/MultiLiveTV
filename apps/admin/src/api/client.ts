const API_BASE = import.meta.env.VITE_API_BASE_URL || "/api/v1";

function getToken(): string | null {
  return localStorage.getItem("admin_token");
}

export function setToken(token: string) {
  localStorage.setItem("admin_token", token);
}

export function clearToken() {
  localStorage.removeItem("admin_token");
}

export function isAuthenticated(): boolean {
  return !!getToken();
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  if (res.status === 401) {
    clearToken();
    window.location.href = "/login";
    throw new Error("未授权");
  }
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || `HTTP ${res.status}`);
  }
  return res.json();
}

export const api = {
  login: (username: string, password: string) =>
    request<{ access_token: string }>("/admin/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    }),

  systemStatus: () => request<SystemStatus>("/admin/system/status"),
  clearCache: () => request<{ ok: boolean }>("/admin/system/cache/clear", { method: "POST" }),
  logs: () => request<{ logs: LogEntry[] }>("/admin/system/logs"),

  listSources: () => request<{ sources: Source[] }>("/admin/sources"),
  createSource: (source: Source) =>
    request<Source>("/admin/sources", { method: "POST", body: JSON.stringify(source) }),
  updateSource: (id: number, source: Source) =>
    request<Source>(`/admin/sources/${id}`, { method: "PUT", body: JSON.stringify(source) }),
  deleteSource: (id: number) =>
    request<{ ok: boolean }>(`/admin/sources/${id}`, { method: "DELETE" }),
  testSource: (id: number) =>
    request<{ ok: boolean; latency: string; error?: string }>(`/admin/sources/${id}/test`, {
      method: "POST",
    }),

  userStats: () => request<UserStats>("/admin/users/stats"),
  listUsers: (page = 1) => request<{ users: UserItem[]; total: number; page: number }>(`/admin/users?page=${page}`),
  deleteUser: (id: string) => request<{ ok: boolean }>(`/admin/users/${id}`, { method: "DELETE" }),
};

export interface Source {
  id: number;
  name: string;
  url: string;
  flag: number;
  jx_url?: string;
  vip_only?: boolean;
}

export interface SystemStatus {
  uptime: string;
  sources: number;
  sources_live: number;
  cache_items: number;
  db: string;
}

export interface LogEntry {
  time: string;
  method: string;
  path: string;
  status: number;
  latency: string;
}

export interface UserStats {
  total_users: number;
  today_new_users: number;
  total_favorites: number;
}

export interface UserItem {
  id: string;
  email: string;
  created_at: string;
  favorite_count: number;
}
