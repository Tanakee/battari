import Foundation

/// 交換確認（G6）で先に見せる相手の情報。uid・ひとことは承認後まで送らない
struct ProfilePreview: Codable, Equatable {
    /// 送り主のアドバタイズ名（交換を終えた相手をしばらく検知しないために使う）
    var token: String = ""
    var displayName: String
    var department: String
    var grade: Int
}

/// 双方が承認した後に送るプロフィール
struct ProfilePayload: Codable, Equatable {
    var uid: String
    var displayName: String
    var department: String
    var grade: Int
    var message: String
}

/// BLEでやりとりするメッセージ。
/// 1件は [種別 1byte][JSON長 4byte][JSON][画像（JPEG）] の形で表す
enum ExchangeMessage: Equatable {
    case hello(ProfilePreview, thumbnail: Data)
    case accept
    case decline
    case profile(ProfilePayload, icon: Data)

    private enum Kind: UInt8 { case hello = 1, accept, decline, profile }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        let (kind, json, binary): (Kind, Data, Data)
        switch self {
        case let .hello(preview, thumbnail): (kind, json, binary) = (.hello, try encoder.encode(preview), thumbnail)
        case .accept: (kind, json, binary) = (.accept, Data(), Data())
        case .decline: (kind, json, binary) = (.decline, Data(), Data())
        case let .profile(payload, icon): (kind, json, binary) = (.profile, try encoder.encode(payload), icon)
        }
        var out = Data([kind.rawValue])
        out.appendUInt32(UInt32(json.count))
        out.append(json)
        out.append(binary)
        return out
    }

    static func decode(_ data: Data) throws -> ExchangeMessage {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, let kind = Kind(rawValue: bytes[0]) else { throw CodecError.malformed }
        let jsonLength = Int(Data(bytes[1..<5]).readUInt32())
        guard bytes.count >= 5 + jsonLength else { throw CodecError.malformed }
        let json = Data(bytes[5..<(5 + jsonLength)])
        let binary = Data(bytes[(5 + jsonLength)...])
        let decoder = JSONDecoder()
        switch kind {
        case .hello: return .hello(try decoder.decode(ProfilePreview.self, from: json), thumbnail: binary)
        case .accept: return .accept
        case .decline: return .decline
        case .profile: return .profile(try decoder.decode(ProfilePayload.self, from: json), icon: binary)
        }
    }
}

enum CodecError: Error { case malformed, tooLarge }

/// メッセージを [全体長 4byte][本体] にして、MTUごとに分割する／受信側で組み立て直す
enum Framing {
    /// 1メッセージの上限（アイコン20KB＋JSONに十分な大きさ）
    static let maxMessageSize = 256 * 1024

    static func chunks(of message: Data, size: Int) -> [Data] {
        precondition(size > 0)
        var framed = Data()
        framed.appendUInt32(UInt32(message.count))
        framed.append(message)
        return stride(from: 0, to: framed.count, by: size).map {
            framed.subdata(in: $0..<min($0 + size, framed.count))
        }
    }
}

/// 分割されて届いたデータを組み立て直す
struct Reassembler {
    private var buffer = Data()

    /// 受け取ったチャンクを追加し、組み上がったメッセージを返す
    mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var messages: [Data] = []
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).readUInt32())
            guard length <= Framing.maxMessageSize else { throw CodecError.tooLarge }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex + 4
            messages.append(buffer.subdata(in: start..<(start + length)))
            buffer = Data(buffer[(start + length)...])
        }
        return messages
    }
}

extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    /// 先頭4byteをビッグエンディアンの UInt32 として読む
    func readUInt32() -> UInt32 {
        let b = [UInt8](prefix(4))
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }
}
