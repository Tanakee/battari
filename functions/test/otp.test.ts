import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CODE_TTL_MS,
  generateCode,
  hashCode,
  isEmail,
  isStudentEmail,
  judge,
  newOtpDoc,
  normalizeEmail,
  resendWaitSeconds,
} from "../src/otp";
import { pageUsers, UserRow } from "../src/users";

const now = new Date("2026-11-16T10:00:00Z");
const email = "s2301234@s.asojuku.ac.jp";

test("学籍メールアドレスの判定", () => {
  assert.ok(isStudentEmail(email));
  assert.ok(isStudentEmail("A1b2C3d4E5f6G7h8I9j0@s.asojuku.ac.jp"));
  assert.ok(!isStudentEmail("A1b2C3d4E5f6G7h8I9j0x@s.asojuku.ac.jp"), "21文字は不可");
  assert.ok(!isStudentEmail("s2301234@asojuku.ac.jp"), "ドメイン違い");
  assert.ok(!isStudentEmail("s23-01@s.asojuku.ac.jp"), "記号は不可");
  assert.ok(!isStudentEmail("@s.asojuku.ac.jp"));
  assert.equal(normalizeEmail("  S2301234@S.ASOJUKU.AC.JP "), email);
});

test("管理者メールアドレスの形式", () => {
  assert.ok(isEmail("admin@asojuku.ac.jp"));
  assert.ok(!isEmail("admin@"));
  assert.ok(!isEmail(`${"a".repeat(250)}@x.jp`));
});

test("コードは6桁の数字", () => {
  for (let i = 0; i < 200; i++) assert.match(generateCode(), /^\d{6}$/);
});

test("正しいコードは成功、期限切れ・用途違いはexpired", () => {
  const doc = newOtpDoc(email, "app", "123456", now);
  assert.deepEqual(judge(doc, "app", "123456", now), { result: "ok" });
  assert.deepEqual(judge(doc, "admin", "123456", now), { result: "expired" });
  assert.deepEqual(judge(undefined, "app", "123456", now), { result: "expired" });
  const later = new Date(now.getTime() + CODE_TTL_MS);
  assert.deepEqual(judge(doc, "app", "123456", later), { result: "expired" });
});

test("5回間違えると無効になる", () => {
  const doc = newOtpDoc(email, "app", "123456", now);
  const seen = [];
  for (let i = 0; i < 5; i++) {
    seen.push(judge(doc, "app", "000000", now));
    doc.attemptCount++;
  }
  assert.deepEqual(seen, [
    { result: "mismatch", remaining: 4 },
    { result: "mismatch", remaining: 3 },
    { result: "mismatch", remaining: 2 },
    { result: "mismatch", remaining: 1 },
    { result: "locked" },
  ]);
  assert.deepEqual(judge(doc, "app", "123456", now), { result: "locked" }, "上限後は正しいコードでも不可");
});

test("ハッシュに平文が含まれない", () => {
  const h = hashCode(email, "123456");
  assert.match(h, /^[0-9a-f]{64}$/);
  assert.notEqual(h, hashCode(email, "123457"));
});

test("再送信は60秒後から", () => {
  const doc = newOtpDoc(email, "app", "123456", now);
  assert.equal(resendWaitSeconds(undefined, now), 0);
  assert.equal(resendWaitSeconds(doc, now), 60);
  assert.equal(resendWaitSeconds(doc, new Date(now.getTime() + 59_001)), 1);
  assert.equal(resendWaitSeconds(doc, new Date(now.getTime() + 60_000)), 0);
});

test("ユーザー一覧の絞り込みとページ分け", () => {
  const all: UserRow[] = Array.from({ length: 45 }, (_, i) => ({
    uid: `u${i}`,
    email: `s${String(i).padStart(7, "0")}@s.asojuku.ac.jp`,
    disabled: i % 3 === 0,
    createdAt: i * 1000,
    lastSignInAt: null,
  }));
  const p1 = pageUsers(all, "", "all", 1);
  assert.equal(p1.totalUsers, 45);
  assert.equal(p1.total, 45);
  assert.equal(p1.users.length, 20);
  assert.equal(p1.users[0].uid, "u44", "登録日時の新しい順");
  assert.equal(pageUsers(all, "", "all", 3).users.length, 5);
  assert.equal(pageUsers(all, "", "all", 99).page, 3, "範囲外は最終ページ");
  assert.equal(pageUsers(all, "", "disabled", 1).total, 15);
  assert.equal(pageUsers(all, "", "enabled", 1).total, 30);
  assert.equal(pageUsers(all, "S000001", "all", 1).total, 10, "大文字小文字を区別しない部分一致");
  const none = pageUsers(all, "zzz", "all", 1);
  assert.equal(none.total, 0);
  assert.equal(none.page, 1);
});
