// BATTARI 管理画面（W1 管理者ログイン / W2 認証コード入力 / W3 ユーザー管理）
import { initializeApp } from "https://www.gstatic.com/firebasejs/13.2.0/firebase-app.js";
import {
  getAuth, onAuthStateChanged, signInWithCustomToken, signOut, connectAuthEmulator,
} from "https://www.gstatic.com/firebasejs/13.2.0/firebase-auth.js";
import {
  getFunctions, httpsCallable, connectFunctionsEmulator,
} from "https://www.gstatic.com/firebasejs/13.2.0/firebase-functions.js";

const REGION = "asia-northeast1";
const RESEND_SECONDS = 60;
const local = location.hostname === "localhost" || location.hostname === "127.0.0.1";

// Firebase Hosting（エミュレータ含む）が配信する設定を読む
const config = await (await fetch("/__/firebase/init.json")).json();
const app = initializeApp(config);
const auth = getAuth(app);
const functions = getFunctions(app, REGION);
if (local) {
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
}
const call = (name, data) => httpsCallable(functions, name)(data).then((r) => r.data);

const $ = (id) => document.getElementById(id);
const show = (id) => {
  for (const s of ["w1", "w2", "w3"]) $(s).hidden = s !== id;
};
const setError = (el, text) => {
  el.textContent = text ?? "";
  el.hidden = !text;
};
const reasonOf = (e) => e?.details?.reason ?? "";

// ---------------- W1 ----------------
const emailInput = $("w1-email");
let email = "";

emailInput.addEventListener("input", () => {
  $("w1-send").disabled = emailInput.value.trim() === "";
});

$("w1-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const value = emailInput.value.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) || value.length > 254) {
    setError($("w1-error"), "メールアドレスを正しく入力してください");
    return;
  }
  setError($("w1-error"), null);
  $("w1-send").disabled = true;
  try {
    await call("requestOtp", { email: value, purpose: "admin" });
    email = value;
    openW2(RESEND_SECONDS);
  } catch (e) {
    const reason = reasonOf(e);
    if (reason === "too-soon") {
      // 送信済みのコードがまだ使えるので、そのまま入力画面へ進む
      email = value;
      openW2(e.details.retryAfter);
      return;
    }
    setError($("w1-error"), {
      "invalid-email": "メールアドレスを正しく入力してください",
      "not-admin": "管理者として登録されていないメールアドレスです",
    }[reason] ?? "送信できませんでした");
  } finally {
    $("w1-send").disabled = emailInput.value.trim() === "";
  }
});

// ---------------- W2 ----------------
const codeBox = $("w2-code");
const cells = Array.from({ length: 6 }, (_, i) => {
  const input = document.createElement("input");
  input.inputMode = "numeric";
  input.maxLength = 1;
  input.autocomplete = i === 0 ? "one-time-code" : "off";
  input.setAttribute("aria-label", `${i + 1}桁目`);
  codeBox.append(input);
  return input;
});
const codeValue = () => cells.map((c) => c.value).join("");
const clearCode = () => {
  for (const c of cells) c.value = "";
  cells[0].focus();
  $("w2-verify").disabled = true;
};

cells.forEach((cell, i) => {
  cell.addEventListener("input", () => {
    const digits = cell.value.replace(/\D/g, "");
    if (digits.length > 1) {
      // 貼り付け・自動入力でまとめて入った場合は後ろのマスへ振り分ける
      digits.slice(0, 6 - i).split("").forEach((d, k) => (cells[i + k].value = d));
      cells[Math.min(i + digits.length, 5)].focus();
    } else {
      cell.value = digits;
      if (digits && i < 5) cells[i + 1].focus();
    }
    $("w2-verify").disabled = !/^\d{6}$/.test(codeValue());
  });
  cell.addEventListener("keydown", (ev) => {
    if (ev.key === "Backspace" && cell.value === "" && i > 0) cells[i - 1].focus();
  });
});

let timer = 0;
function startCountdown(seconds) {
  clearInterval(timer);
  let left = seconds;
  const btn = $("w2-resend");
  const tick = () => {
    btn.disabled = left > 0;
    btn.textContent = left > 0 ? `再送信（${left}秒後）` : "再送信";
    left--;
    if (left < 0) clearInterval(timer);
  };
  tick();
  timer = setInterval(tick, 1000);
}

function openW2(wait) {
  $("w2-address").textContent = email;
  setError($("w2-error"), null);
  $("w2-info").hidden = true;
  show("w2");
  clearCode();
  startCountdown(wait);
}

$("w2-back").addEventListener("click", () => {
  clearInterval(timer);
  show("w1");
  emailInput.focus();
});

$("w2-resend").addEventListener("click", async () => {
  $("w2-resend").disabled = true;
  setError($("w2-error"), null);
  $("w2-info").hidden = true;
  try {
    await call("requestOtp", { email, purpose: "admin" });
    $("w2-info").textContent = "再送信しました";
    $("w2-info").hidden = false;
    clearCode();
    startCountdown(RESEND_SECONDS);
  } catch (e) {
    if (reasonOf(e) === "too-soon") return startCountdown(e.details.retryAfter);
    setError($("w2-error"), "送信できませんでした");
    $("w2-resend").disabled = false;
  }
});

$("w2-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  $("w2-verify").disabled = true;
  $("w2-info").hidden = true;
  try {
    const { token } = await call("verifyOtp", { email, code: codeValue(), purpose: "admin" });
    clearInterval(timer);
    await signInWithCustomToken(auth, token); // 以降は onAuthStateChanged が W3 を開く
  } catch (e) {
    const reason = reasonOf(e);
    setError($("w2-error"), {
      mismatch: `コードが正しくありません（残り${e.details?.remaining}回）`,
      expired: "有効期限が切れています。再送信してください",
      locked: "入力回数の上限に達しました。再送信してください",
      disabled: "このアカウントは無効化されています",
      "not-admin": "管理者として登録されていないメールアドレスです",
    }[reason] ?? "認証できませんでした");
    clearCode();
  }
});

// ---------------- W3 ----------------
const state = { query: "", status: "all", page: 1, total: 0, pageSize: 20 };
const fmt = new Intl.DateTimeFormat("ja-JP", {
  year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false,
});
const fmtDate = (ms) => (ms == null ? "-" : fmt.format(new Date(ms)));
const capped = (n, max) => (n > max ? `${max}+` : String(n));

function toast(text, error = false) {
  const el = $("toast");
  el.textContent = text;
  el.className = error ? "error" : "";
  el.hidden = false;
  clearTimeout(toast.t);
  toast.t = setTimeout(() => (el.hidden = true), 2500);
}

function cell(tag, className, text) {
  const el = document.createElement(tag);
  if (className) el.className = className;
  if (text != null) el.textContent = text;
  return el;
}

function renderRows(users) {
  const body = $("w3-rows");
  body.replaceChildren();
  if (users.length === 0) {
    const tr = document.createElement("tr");
    const td = cell("td", "empty", "該当するユーザーはいません");
    td.colSpan = 6;
    tr.append(td);
    body.append(tr);
    return;
  }
  for (const u of users) {
    const tr = document.createElement("tr");
    const uid = cell("td", "mono", u.uid.length > 10 ? `${u.uid.slice(0, 10)}…` : u.uid);
    uid.title = u.uid;
    const status = cell("td");
    status.append(cell("span", `pill ${u.disabled ? "off" : "on"}`, u.disabled ? "無効" : "有効"));
    const ops = cell("td");
    const toggle = cell("button", "sbtn", u.disabled ? "有効化" : "無効化");
    toggle.addEventListener("click", () => setDisabled(u, !u.disabled, toggle));
    const del = cell("button", "sbtn red", "削除");
    del.addEventListener("click", () => confirmDelete(u));
    ops.append(toggle, del);
    tr.append(uid, cell("td", "email", u.email), cell("td", "date", fmtDate(u.createdAt)),
      cell("td", "date", fmtDate(u.lastSignInAt)), status, ops);
    body.append(tr);
  }
}

let loadSeq = 0;
async function load() {
  const seq = ++loadSeq;
  try {
    const res = await call("adminListUsers", { query: state.query, status: state.status, page: state.page });
    if (seq !== loadSeq) return; // 古い検索結果は捨てる
    Object.assign(state, { page: res.page, total: res.total, pageSize: res.pageSize });
    $("w3-total").textContent = capped(res.totalUsers, 999999);
    renderRows(res.users);
    const from = res.total === 0 ? 0 : (res.page - 1) * res.pageSize + 1;
    const to = Math.min(res.page * res.pageSize, res.total);
    $("w3-range").textContent = `${from}〜${to}件 / ${res.total}件`;
    $("w3-prev").disabled = res.page <= 1;
    $("w3-next").disabled = to >= res.total;
  } catch (e) {
    if (seq !== loadSeq) return;
    if (e.code === "functions/permission-denied" || e.code === "functions/unauthenticated") return signOut(auth);
    toast("一覧を取得できませんでした", true);
  }
}

async function setDisabled(user, disabled, button) {
  button.disabled = true;
  try {
    await call("adminSetDisabled", { uid: user.uid, disabled });
    toast(disabled ? "無効化しました" : "有効化しました");
    await load();
  } catch {
    toast("更新できませんでした", true);
    button.disabled = false;
  }
}

let deleting = null;
function confirmDelete(user) {
  deleting = user;
  $("confirm-email").textContent = user.email;
  $("confirm").showModal();
}
$("confirm-cancel").addEventListener("click", () => $("confirm").close());
$("confirm-ok").addEventListener("click", async () => {
  $("confirm").close();
  try {
    await call("adminDeleteUser", { uid: deleting.uid });
    toast("削除しました");
    await load();
  } catch {
    toast("削除できませんでした", true);
  }
});

$("w3-query").addEventListener("input", () => {
  state.query = $("w3-query").value;
  state.page = 1;
  load();
});
for (const b of $("w3-status").querySelectorAll("button")) {
  b.addEventListener("click", () => {
    for (const o of $("w3-status").querySelectorAll("button")) o.setAttribute("aria-checked", String(o === b));
    state.status = b.dataset.v;
    state.page = 1;
    load();
  });
}
$("w3-prev").addEventListener("click", () => { state.page--; load(); });
$("w3-next").addEventListener("click", () => { state.page++; load(); });
$("w3-logout").addEventListener("click", () => signOut(auth));

// ---------------- ログイン状態 ----------------
onAuthStateChanged(auth, async (user) => {
  if (!user) {
    if (!$("w2").hidden) return; // W2で入力中ならそのまま
    show("w1");
    emailInput.focus();
    return;
  }
  const { claims } = await user.getIdTokenResult();
  if (claims.admin !== true) {
    // 管理者権限がなければログアウトしてW1へ
    await signOut(auth);
    return;
  }
  $("w3-me").textContent = user.email ?? "";
  $("w3-me").title = user.email ?? "";
  show("w3");
  load();
});
