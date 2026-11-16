import UIKit

/// 原版视觉语言：白底红点缀的浏览页 + 纯黑播放器。
enum Theme {
    static let red = UIColor(hex: 0xF5333F)
    static let redDark = UIColor(hex: 0xE01F14)
    static let redLight = UIColor(hex: 0xFF6B5C)
    static let background = UIColor(hex: 0xFFFFFF)
    static let groupedBackground = UIColor(hex: 0xF7F7F9)
    static let card = UIColor.white
    static let ink = UIColor(hex: 0x141418)
    static let secondary = UIColor(hex: 0x9A9AA2)
    static let softRed = UIColor(hex: 0xFFE9E9)
    static let hairline = UIColor(hex: 0xEDEDF1)
    static let chip = UIColor(hex: 0xF2F2F6)
    static let cardBorder = UIColor(hex: 0xF4E3E3)

    static let playerBlack = UIColor(hex: 0x000000)
    static let playerControl = UIColor(hex: 0x2C2C2E)
    static let playerBar = UIColor(hex: 0x1C1C1E)
    /// 顶部圆形按钮：接近原版的半透明深灰。
    static let playerCircle = UIColor(white: 0.16, alpha: 0.94)
    /// 底部控制胶囊。
    static let playerPill = UIColor(white: 0.09, alpha: 0.94)
    /// 亮度滑杆的进度色（参考图里的暖黄）。
    static let playerAccent = UIColor(hex: 0xFFC53D)

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 卡片阴影统一入口，避免每处重复调参。
    static func applyCardShadow(_ view: UIView, radius: CGFloat = 16, opacity: Float = 0.06) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = opacity
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.layer.shadowRadius = radius
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

/// 首页主卡片的红色渐变底（左上亮、右下深，贴近原版）。
final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    var gradientLayer: CAGradientLayer? { layer as? CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        gradientLayer?.colors = [UIColor(hex: 0xF8463A).cgColor, UIColor(hex: 0xDD1C12).cgColor]
        gradientLayer?.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer?.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer?.cornerRadius = 18
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.cornerRadius = min(18, bounds.height / 5)
    }
}

enum Controls {
    /// 播放器顶部/底部的圆形按钮。
    static func roundButton(systemName: String,
                            accessibility: String,
                            diameter: CGFloat = 44,
                            background: UIColor = Theme.playerControl,
                            pointSize: CGFloat = 17) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = background
        button.layer.cornerRadius = diameter / 2
        button.clipsToBounds = true
        button.accessibilityLabel = accessibility
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// 首页右上角的浅灰圆形入口。
    static func chipButton(systemName: String, accessibility: String, diameter: CGFloat = 34) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = Theme.ink
        button.backgroundColor = Theme.chip
        button.layer.cornerRadius = diameter / 2
        button.clipsToBounds = true
        button.accessibilityLabel = accessibility
        return button
    }
}

/// 播放器按钮的图像工厂。
///
/// 顶部有 7 个按钮，其中 "HQ" 与 "Tt" 在 SF Symbols 里没有对应字形，
/// 这里按参考图用 Core Graphics 直接画出来，避免依赖系统字形的存在性。
enum PlayerGlyph {

    /// 依次尝试多个 SF Symbol 名，返回第一个在当前系统上可用的。
    static func symbol(_ names: [String],
                       pointSize: CGFloat = 17,
                       weight: UIImage.SymbolWeight = .semibold) -> UIImage? {
        for name in names {
            if let image = UIImage(systemName: name,
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize,
                                                                                  weight: weight)) {
                return image.withRenderingMode(.alwaysTemplate)
            }
        }
        return nil
    }

    /// 文本型图标（HQ / Tt 兜底）：按文字实际尺寸紧密渲染并光学居中，
    /// 无外框，保持与其它 SF Symbol 图标一致的扁平观感。
    static func text(_ string: String, fontSize: CGFloat, weight: UIFont.Weight = .heavy) -> UIImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: UIColor.white
        ]
        let textSize = (string as NSString).size(withAttributes: attributes)
        let size = CGSize(width: ceil(textSize.width) + 4, height: ceil(textSize.height) + 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let origin = CGPoint(x: (size.width - textSize.width) / 2,
                                 y: (size.height - textSize.height) / 2)
            (string as NSString).draw(at: origin, withAttributes: attributes)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

/// 圆角矩形图标底板（首页品牌方块 / 引擎方块 / 列表缩略图共用）。
final class RoundedIconView: UIView {
    let imageView = UIImageView()

    init(symbol: String, size: CGFloat, background: UIColor, tint: UIColor, corner: CGFloat = 12) {
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        backgroundColor = background
        layer.cornerRadius = corner
        clipsToBounds = true
        imageView.image = UIImage(systemName: symbol,
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.44, weight: .bold))
        imageView.tintColor = tint
        imageView.contentMode = .center
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 播放器内文字（提示 / 详情面板）字号档位。
enum TextScale: Int, CaseIterable {
    case small = 0
    case standard = 1
    case large = 2

    var multiplier: CGFloat {
        switch self {
        case .small: return 0.88
        case .standard: return 1.0
        case .large: return 1.18
        }
    }

    var titleKey: String {
        switch self {
        case .small: return "player.textSmall"
        case .standard: return "player.textStandard"
        case .large: return "player.textLarge"
        }
    }
}

/// 用户偏好：自动播放 / 启动静音 / 播放器字号。
enum PlaybackPreferences {
    private static let autoPlayKey = "community.swfplayer.autoplay"
    private static let startMutedKey = "community.swfplayer.startMuted"
    private static let textScaleKey = "community.swfplayer.textScale"

    static var autoPlay: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoPlayKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: autoPlayKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoPlayKey) }
    }

    static var startMuted: Bool {
        get { UserDefaults.standard.bool(forKey: startMutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: startMutedKey) }
    }

    static var textScale: TextScale {
        get {
            let raw = UserDefaults.standard.integer(forKey: textScaleKey)
            return TextScale(rawValue: raw) ?? .standard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: textScaleKey) }
    }
}
