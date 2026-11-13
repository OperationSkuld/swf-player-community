import UIKit

/// 沿用原版"红 + 米白 / 纯黑播放器"的视觉语言。
enum Theme {
    static let red = UIColor(hex: 0xF5333F)
    static let redLight = UIColor(hex: 0xFF6B5C)
    static let background = UIColor(hex: 0xFAF7F6)
    static let card = UIColor.white
    static let ink = UIColor(hex: 0x1B1B1F)
    static let secondary = UIColor(hex: 0x8B8B90)
    static let softRed = UIColor(hex: 0xFFE9E9)
    static let playerBlack = UIColor(hex: 0x000000)
    static let controlBackground = UIColor(white: 0.12, alpha: 0.92)

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

/// 首页主按钮的红色渐变底。
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
        gradientLayer?.colors = [Theme.red.cgColor, Theme.redLight.cgColor]
        gradientLayer?.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer?.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer?.cornerRadius = 20
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.cornerRadius = min(20, bounds.height / 6)
    }
}

enum Controls {
    /// 播放器工具栏里的圆形半透明按钮。
    static func roundButton(systemName: String, accessibility: String) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = Theme.controlBackground
        button.layer.cornerRadius = 20
        button.clipsToBounds = true
        button.accessibilityLabel = accessibility
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
