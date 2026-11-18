import Foundation

enum Validation {
    /// G1: 学籍番号（メールアドレスの@より前）の判定結果
    enum StudentId: Equatable {
        case valid(String), empty, format

        var errorMessage: String? {
            switch self {
            case .valid: return nil
            case .empty: return "学籍番号を入力してください"
            case .format: return "半角英数字20文字以内で入力してください"
            }
        }
    }

    /// 前後の空白を除き、^[A-Za-z0-9]{1,20}$ に一致するか
    static func studentId(_ raw: String) -> StudentId {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return .empty }
        let ok = value.count <= Limits.studentIdLength && value.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }
        return ok ? .valid(value) : .format
    }

    static func studentEmail(_ studentId: String) -> String {
        "\(studentId.lowercased())@\(School.mailDomain)"
    }

    /// G3: 表示名（前後の空白を除いて1〜20文字）
    static func displayName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.count > Limits.displayNameLength ? nil : value
    }

    /// 入力欄に上限を超えて入らないように切り詰める
    static func truncated(_ value: String, to limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) : value
    }

    /// G2: 6桁の数字
    static func isOtp(_ value: String) -> Bool {
        value.count == Limits.otpLength && value.allSatisfy(\.isASCII) && value.allSatisfy(\.isNumber)
    }
}

enum Format {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    /// yyyy/MM/dd HH:mm
    static func dateTime(_ date: Date) -> String { dateFormatter.string(from: date) }

    /// G4: 9999を超えたら「9999+」
    static func stickerCount(_ n: Int) -> String { n > 9999 ? "9999+" : "\(n)" }
}
