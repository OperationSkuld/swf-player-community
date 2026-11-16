import Foundation

/// 本版本的功能开关集中放在这里，便于审查。
///
/// 说明：这是一个从零编写的独立实现，源码、图标与资源均不包含原 App 的二进制、
/// 代码或素材。因此这里根本不存在 VIP 判定、播放次数计数、StoreKit 内购或功能门控，
/// 而不是"绕过"了某个校验。
enum BuildInfo {
    static let appVersion = "2.2.0"
    static let buildNumber = "1"
    static let edition = "Community Edition"

    /// 永远为 false：保留此常量只是为了让"无 VIP 限制"这一事实在代码中显式可查。
    static let vipLimitEnabled = false
    /// 没有次数上限（nil = 无限）。
    static let maxPlayCount: Int? = nil
    static let hasInAppPurchases = false
    static let requiresNetwork = false

    static var ruffleVersion: String {
        let candidates = [
            Bundle.main.url(forResource: "RUFFLE_VERSION", withExtension: nil, subdirectory: "Web"),
            Bundle.main.url(forResource: "RUFFLE_VERSION", withExtension: nil)
        ]
        for url in candidates.compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return "not bundled"
    }

    static func humanReadableSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
