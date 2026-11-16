// 認証コードのメール送信（SendGrid）
import sgMail from "@sendgrid/mail";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import type { Purpose } from "./otp";

const SENDGRID_API_KEY = defineSecret("SENDGRID_API_KEY");
const MAIL_FROM = defineString("MAIL_FROM", { description: "認証コードメールの送信元アドレス（SendGridで認証済みのもの）" });

export const MAIL_SECRETS = [SENDGRID_API_KEY];

export async function sendOtpMail(to: string, code: string, purpose: Purpose): Promise<void> {
  // エミュレータでAPIキーを設定していないときは、送らずにログへ出す
  if (process.env.FUNCTIONS_EMULATOR === "true" && !SENDGRID_API_KEY.value()) {
    logger.info(`[emulator] ${to} への認証コード: ${code}`);
    return;
  }
  sgMail.setApiKey(SENDGRID_API_KEY.value());
  const who = purpose === "admin" ? "BATTARI 管理画面" : "BATTARI";
  await sgMail.send({
    to,
    from: { email: MAIL_FROM.value(), name: "BATTARI" },
    subject: `【${who}】認証コード ${code}`,
    text: [
      `${who}の認証コードは ${code} です。`,
      "",
      "有効期限は10分です。5回間違えると無効になります。",
      "心当たりがない場合は、このメールを破棄してください。",
    ].join("\n"),
  });
}
