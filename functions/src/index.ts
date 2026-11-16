// BATTARI の Cloud Functions
//   学内メール認証（G1・G2）と管理者ログイン（W1・W2）: requestOtp / verifyOtp
//   ユーザー管理（W3）: adminListUsers / adminSetDisabled / adminDeleteUser
import { initializeApp } from "firebase-admin/app";
import { getAuth, UserRecord } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { sendOtpMail, MAIL_SECRETS } from "./mail";
import {
  generateCode,
  isEmail,
  isPurpose,
  isStudentEmail,
  judge,
  newOtpDoc,
  normalizeEmail,
  OtpDoc,
  Purpose,
  resendWaitSeconds,
} from "./otp";
import { isStatusFilter, pageUsers, UserRow } from "./users";

initializeApp();
setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });

const db = getFirestore();
const auth = getAuth();
const otpRef = (email: string) => db.collection("otpCodes").doc(email);
const adminRef = (email: string) => db.collection("admins").doc(email);

// クライアントは details.reason を見てエラーメッセージを出し分ける
function fail(code: ConstructorParameters<typeof HttpsError>[0], reason: string, extra: object = {}): never {
  throw new HttpsError(code, reason, { reason, ...extra });
}

function readOtp(data: FirebaseFirestore.DocumentData | undefined): OtpDoc | undefined {
  if (!data) return undefined;
  return {
    email: data.email,
    codeHash: data.codeHash,
    purpose: data.purpose,
    expiresAt: (data.expiresAt as Timestamp).toDate(),
    attemptCount: data.attemptCount,
    createdAt: (data.createdAt as Timestamp).toDate(),
  };
}

function parseEmail(raw: unknown, purpose: Purpose): string {
  const email = typeof raw === "string" ? normalizeEmail(raw) : "";
  if (purpose === "app" ? !isStudentEmail(email) : !isEmail(email)) fail("invalid-argument", "invalid-email");
  return email;
}

function parsePurpose(raw: unknown): Purpose {
  if (!isPurpose(raw)) fail("invalid-argument", "invalid-purpose");
  return raw;
}

async function findUser(email: string): Promise<UserRecord | undefined> {
  try {
    return await auth.getUserByEmail(email);
  } catch (e) {
    if ((e as { code?: string }).code === "auth/user-not-found") return undefined;
    throw e;
  }
}

/** 認証コードを発行してメールで送る（再送信も同じ） */
export const requestOtp = onCall({ secrets: MAIL_SECRETS }, async (req) => {
  const purpose = parsePurpose(req.data?.purpose);
  const email = parseEmail(req.data?.email, purpose);

  if (purpose === "admin" && !(await adminRef(email).get()).exists) fail("not-found", "not-admin");

  const now = new Date();
  const wait = resendWaitSeconds(readOtp((await otpRef(email).get()).data()), now);
  if (wait > 0) fail("resource-exhausted", "too-soon", { retryAfter: wait });

  const code = generateCode();
  await otpRef(email).set(newOtpDoc(email, purpose, code, now));
  try {
    await sendOtpMail(email, code, purpose);
  } catch (e) {
    logger.error("OTPメールの送信に失敗", e);
    await otpRef(email).delete();
    fail("unavailable", "send-failed");
  }
  return { resendAfter: 60 };
});

/** 認証コードを検証し、成功したらカスタムトークンを返す */
export const verifyOtp = onCall(async (req) => {
  const purpose = parsePurpose(req.data?.purpose);
  const email = parseEmail(req.data?.email, purpose);
  const code = typeof req.data?.code === "string" ? req.data.code : "";
  if (!/^\d{6}$/.test(code)) fail("invalid-argument", "invalid-code");

  const verdict = await db.runTransaction(async (tx) => {
    const snap = await tx.get(otpRef(email));
    const doc = readOtp(snap.data());
    const v = judge(doc, purpose, code, new Date());
    if (v.result === "mismatch" || v.result === "locked") {
      if (doc) tx.update(otpRef(email), { attemptCount: doc.attemptCount + 1 });
    } else if (snap.exists) {
      tx.delete(otpRef(email)); // 成功・期限切れのどちらでも消す
    }
    return v;
  });
  if (verdict.result === "expired") fail("deadline-exceeded", "expired");
  if (verdict.result === "locked") fail("resource-exhausted", "locked");
  if (verdict.result === "mismatch") fail("invalid-argument", "mismatch", { remaining: verdict.remaining });

  const user = (await findUser(email)) ?? (await auth.createUser({ email, emailVerified: true }));
  if (user.disabled) fail("permission-denied", "disabled");

  if (purpose === "admin") {
    if (!(await adminRef(email).get()).exists) fail("permission-denied", "not-admin");
    if (user.customClaims?.admin !== true) {
      await auth.setCustomUserClaims(user.uid, { ...user.customClaims, admin: true });
    }
    return { token: await auth.createCustomToken(user.uid, { admin: true }) };
  }
  return { token: await auth.createCustomToken(user.uid) };
});

// ---------------- 管理（W3） ----------------

function requireAdmin(req: CallableRequest): string {
  if (req.auth?.token.admin !== true) fail("permission-denied", "not-admin");
  return req.auth.uid;
}

async function listAllUsers(): Promise<UserRow[]> {
  const rows: UserRow[] = [];
  let pageToken: string | undefined;
  do {
    const res = await auth.listUsers(1000, pageToken);
    for (const u of res.users) {
      if (u.customClaims?.admin === true) continue; // 管理者は一覧に出さない
      rows.push({
        uid: u.uid,
        email: u.email ?? "",
        disabled: u.disabled,
        createdAt: Date.parse(u.metadata.creationTime),
        lastSignInAt: u.metadata.lastSignInTime ? Date.parse(u.metadata.lastSignInTime) : null,
      });
    }
    pageToken = res.pageToken;
  } while (pageToken);
  return rows;
}

/** 操作対象が一般ユーザーであることを確かめる（管理者は操作させない） */
async function targetUser(raw: unknown): Promise<UserRecord> {
  if (typeof raw !== "string" || raw === "") fail("invalid-argument", "invalid-uid");
  try {
    const user = await auth.getUser(raw);
    if (user.customClaims?.admin === true) fail("permission-denied", "target-is-admin");
    return user;
  } catch (e) {
    if ((e as { code?: string }).code === "auth/user-not-found") fail("not-found", "user-not-found");
    throw e;
  }
}

export const adminListUsers = onCall(async (req) => {
  requireAdmin(req);
  const query = typeof req.data?.query === "string" ? req.data.query : "";
  const status = isStatusFilter(req.data?.status) ? req.data.status : "all";
  const page = typeof req.data?.page === "number" ? req.data.page : 1;
  return pageUsers(await listAllUsers(), query, status, page);
});

export const adminSetDisabled = onCall(async (req) => {
  requireAdmin(req);
  const user = await targetUser(req.data?.uid);
  if (typeof req.data?.disabled !== "boolean") fail("invalid-argument", "invalid-disabled");
  await auth.updateUser(user.uid, { disabled: req.data.disabled });
  if (req.data.disabled) await auth.revokeRefreshTokens(user.uid); // 次のトークン更新で締め出す
  return { uid: user.uid, disabled: req.data.disabled };
});

export const adminDeleteUser = onCall(async (req) => {
  requireAdmin(req);
  const user = await targetUser(req.data?.uid);
  await auth.deleteUser(user.uid);
  return { uid: user.uid };
});
