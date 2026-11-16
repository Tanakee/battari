import UIKit

/// アイコン画像の加工（正方形に切り抜き・縮小・JPEG化、頭文字アイコンの生成）
enum ImageTools {
    /// 正方形に切り抜いて size×size に縮小し、maxBytes 以内のJPEGにする
    static func iconJPEG(from image: UIImage, size: Int = Limits.iconSize, maxBytes: Int = Limits.iconMaxBytes) -> Data? {
        let square = squareResized(image, side: CGFloat(size))
        var quality: CGFloat = 0.85
        while quality > 0.1 {
            if let data = square.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
            quality -= 0.1
        }
        return square.jpegData(compressionQuality: 0.1)
    }

    static func squareResized(_ image: UIImage, side: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let scale = side / min(w, h)
        let drawSize = CGSize(width: w * scale, height: h * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }

    /// 表示名の頭文字から作るアイコン（画像を選ばずに保存した場合）
    static func initialIcon(for name: String, size: Int = Limits.iconSize) -> Data {
        let side = CGFloat(size)
        let initial = name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "?"
        let (top, bottom) = Palette.gradient(for: name)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            let font = UIFont.systemFont(ofSize: side * 0.46, weight: .heavy)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.25)
            shadow.shadowOffset = CGSize(width: 0, height: side * 0.01)
            shadow.shadowBlurRadius = side * 0.02
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .shadow: shadow]
            let text = initial as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2), withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }

    /// 交換確認（G6）で先に見せる小さいアイコン
    static func thumbnail(_ jpeg: Data, side: Int = 96) -> Data {
        guard let image = UIImage(data: jpeg) else { return jpeg }
        return squareResized(image, side: CGFloat(side)).jpegData(compressionQuality: 0.7) ?? jpeg
    }
}

enum Palette {
    private static let pairs: [(UInt32, UInt32)] = [
        (0xFF8A5B, 0xF2416B), (0x4FA8F5, 0x5B5BD6), (0x6FD08C, 0x23A06B), (0xFFC84A, 0xF29A1F),
        (0xB57CF5, 0x7B3FE0), (0xF26BB0, 0xD8336D), (0x2DD4BF, 0x0E9FCF), (0x5B9BF5, 0x2F5FE0),
        (0x9BDB4D, 0x2FA84F), (0xFFA36B, 0xF0601F), (0x8C9BFF, 0x5B6BEA), (0xFF7A7A, 0xE5484D),
    ]

    /// 名前から決まるグラデーション（同じ名前なら同じ色）
    static func gradient(for key: String) -> (UIColor, UIColor) {
        let (a, b) = pairs[Int(stableHash(key) % UInt64(pairs.count))]
        return (UIColor(hex: a), UIColor(hex: b))
    }

    /// 実行ごとに変わらないハッシュ（FNV-1a）
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
