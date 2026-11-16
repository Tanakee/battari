// 管理画面（W3）のユーザー一覧の絞り込み・並べ替え・ページ分け
export const PAGE_SIZE = 20;

export type StatusFilter = "all" | "enabled" | "disabled";

export interface UserRow {
  uid: string;
  email: string;
  disabled: boolean;
  createdAt: number; // epoch ms
  lastSignInAt: number | null;
}

export interface UserPage {
  totalUsers: number; // 管理者を除く登録ユーザー数
  total: number; // 絞り込み後の件数
  page: number; // 1始まり
  pageSize: number;
  users: UserRow[];
}

export function isStatusFilter(value: unknown): value is StatusFilter {
  return value === "all" || value === "enabled" || value === "disabled";
}

export function pageUsers(all: UserRow[], query: string, status: StatusFilter, page: number): UserPage {
  const q = query.trim().toLowerCase();
  const hits = all
    .filter((u) => status === "all" || (status === "disabled") === u.disabled)
    .filter((u) => q === "" || u.email.toLowerCase().includes(q))
    .sort((a, b) => b.createdAt - a.createdAt);
  const lastPage = Math.max(1, Math.ceil(hits.length / PAGE_SIZE));
  const current = Math.min(Math.max(1, Math.floor(page) || 1), lastPage);
  return {
    totalUsers: all.length,
    total: hits.length,
    page: current,
    pageSize: PAGE_SIZE,
    users: hits.slice((current - 1) * PAGE_SIZE, current * PAGE_SIZE),
  };
}
