// 認証コード（OTP）の判定ロジック。Firestore や Firebase Auth に依存しない部分だけを置く
import { createHash, randomInt } from "node:crypto";

export const STUDENT_DOMAIN = "s.asojuku.ac.jp";
export const CODE_TTL_MS = 10 * 60 * 1000; // 有効期限10分
export const MAX_ATTEMPTS = 5; // 5回失敗で無効
export const RESEND_INTERVAL_MS = 60 * 1000; // 再送信は60秒後から

export type Purpose = "app" | "admin";

export interface OtpDoc {
  email: string;
  codeHash: string;
  purpose: Purpose;
  expiresAt: Date;
  attemptCount: number;
  createdAt: Date;
}

const STUDENT_ID = /^[A-Za-z0-9]{1,20}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/** 学籍メールアドレス（学籍番号＋@s.asojuku.ac.jp）か */
export function isStudentEmail(email: string): boolean {
  const at = email.lastIndexOf("@");
  if (at < 0) return false;
  return STUDENT_ID.test(email.slice(0, at)) && email.slice(at + 1) === STUDENT_DOMAIN;
}

/** 管理者用のメールアドレス形式チェック（254文字以内） */
export function isEmail(email: string): boolean {
  return email.length <= 254 && EMAIL.test(email);
}

export function isPurpose(value: unknown): value is Purpose {
  return value === "app" || value === "admin";
}

export function generateCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, "0");
}

/** 平文は保存しないため、SHA-256 のハッシュだけを残す */
export function hashCode(email: string, code: string): string {
  return createHash("sha256").update(`${email}:${code}`).digest("hex");
}

export function newOtpDoc(email: string, purpose: Purpose, code: string, now: Date): OtpDoc {
  return {
    email,
    codeHash: hashCode(email, code),
    purpose,
    expiresAt: new Date(now.getTime() + CODE_TTL_MS),
    attemptCount: 0,
    createdAt: now,
  };
}

/** 前回の送信から60秒経っていなければ、あと何秒待つかを返す */
export function resendWaitSeconds(prev: Pick<OtpDoc, "createdAt"> | undefined, now: Date): number {
  if (!prev) return 0;
  const left = prev.createdAt.getTime() + RESEND_INTERVAL_MS - now.getTime();
  return left > 0 ? Math.ceil(left / 1000) : 0;
}

export type Verdict =
  | { result: "ok" }
  | { result: "expired" } // コードがない・期限切れ・用途違い
  | { result: "locked" } // 入力回数の上限に達した
  | { result: "mismatch"; remaining: number };

/**
 * 入力されたコードを判定する。
 * mismatch のときは attemptCount を1増やして保存すること（呼び出し側の責任）
 */
export function judge(doc: OtpDoc | undefined, purpose: Purpose, code: string, now: Date): Verdict {
  if (!doc || doc.purpose !== purpose) return { result: "expired" };
  if (doc.expiresAt.getTime() <= now.getTime()) return { result: "expired" };
  if (doc.attemptCount >= MAX_ATTEMPTS) return { result: "locked" };
  if (doc.codeHash === hashCode(doc.email, code)) return { result: "ok" };
  const remaining = MAX_ATTEMPTS - (doc.attemptCount + 1);
  return remaining > 0 ? { result: "mismatch", remaining } : { result: "locked" };
}
