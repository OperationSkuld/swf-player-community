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

/// 用户偏好：自动播放 / 启动静音 / 语言以外的播放设置。
enum PlaybackPreferences {
    private static let autoPlayKey = "community.swfplayer.autoplay"
    private static let startMutedKey = "community.swfplayer.startMuted"

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
}
