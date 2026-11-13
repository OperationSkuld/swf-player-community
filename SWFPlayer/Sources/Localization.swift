import Foundation

/// 应用内语言偏好。`.system` 跟随系统，其余为用户强制指定的语言。
enum AppLanguage: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case ja
    case en

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("appLanguageDidChange")
}

/// 轻量字符串表：中文 / 日文 / 英文三语，支持应用内即时切换（不依赖 .lproj 目录结构）。
/// 这样做的目的是让 "系统语言为日语但用户想用中文" 的场景也能生效。
final class L10n {
    static let shared = L10n()

    private static let defaultsKey = "community.swfplayer.language"
    private init() {}

    var preference: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppLanguage.system.rawValue
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    var effective: AppLanguage {
        let pref = preference
        if pref != .system { return pref }
        let identifier = Bundle.main.preferredLocalizations.first
            ?? Locale.current.languageCode
            ?? "en"
        if identifier.hasPrefix("zh") { return .zhHans }
        if identifier.hasPrefix("ja") { return .ja }
        return .en
    }

    func t(_ key: String) -> String {
        if let value = tables[effective]?[key], !value.isEmpty { return value }
        if let value = tables[.en]?[key], !value.isEmpty { return value }
        return key
    }

    // swiftlint:disable:next colon
    private let tables: [AppLanguage: [String: String]] = [
        .en: [
            "common.ok": "OK",
            "common.cancel": "Cancel",
            "common.delete": "Delete",
            "common.error": "Error",
            "home.brandSub": "Classic Red & White · Professional Play",
            "home.freeBadge": "All features free · No play-count limits",
            "home.importTitle": "Select Local SWF File",
            "home.importSub": "Unlock immersive Flash memories",
            "home.recent": "Recent Plays",
            "home.emptyTitle": "No SWF files yet",
            "home.emptyHint": "Tap the red card above, or drop a .swf file into the app's Documents folder via Finder / iTunes.",
            "home.lastPlayed": "Last played: %@",
            "home.neverPlayed": "Not played yet",
            "home.deleteAction": "Remove",
            "home.deleteConfirmTitle": "Remove this file?",
            "home.deleteConfirmMessage": "The imported SWF will be deleted from this device.",
            "home.importErrorTitle": "Import failed",
            "home.importErrorUnsupported": "Only .swf files are supported.",
            "home.importErrorInvalid": "This file is not a valid SWF (missing FWS / CWS / ZWS signature).",
            "home.importErrorGeneric": "Could not read the selected file.",
            "home.shareAction": "Share",
            "settings.title": "Settings",
            "settings.done": "Done",
            "settings.sectionLanguage": "Language / 言語",
            "settings.languageHint": "Applies immediately, no restart needed.",
            "settings.sectionAbout": "About this build",
            "settings.sectionData": "Data",
            "settings.aboutText": "An independent, clean-room reimplementation inspired by the original SWF Player interface. Rendering is powered by the Ruffle Flash emulator. No VIP tiers, no play-count counters, no in-app purchases, no ads and no network access.",
            "settings.version": "Version",
            "settings.edition": "Edition",
            "settings.engine": "Rendering engine: Ruffle %@",
            "settings.noLimits": "Restrictions: none",
            "settings.license": "Open-source licenses",
            "settings.licenseText": "Ruffle is dual-licensed under MIT OR Apache-2.0. The full license texts are bundled inside the app at Web/LICENSE_MIT and Web/LICENSE_APACHE.",
            "settings.clearHistory": "Clear play history",
            "settings.clearHistoryTitle": "Clear all imported files?",
            "settings.clearHistoryMessage": "All imported SWF files and cached covers will be removed.",
            "settings.clearAction": "Clear all",
            "player.loading": "Loading SWF…",
            "player.loadFailedTitle": "Could not play this SWF",
            "player.loadFailedMessage": "The Ruffle engine could not load the file. It may use unsupported ActionScript features.",
            "player.engineMissing": "The Ruffle engine assets are missing from this build. Run Scripts/fetch-ruffle.sh before building.",
            "player.retryAction": "Retry",
            "player.back": "Back",
            "player.mute": "Mute",
            "player.unmute": "Unmute",
            "player.snapshot": "Screenshot",
            "player.info": "File info",
            "player.fullscreen": "Fullscreen",
            "player.exitFullscreen": "Exit fullscreen",
            "player.restart": "Restart",
            "player.play": "Play",
            "player.pause": "Pause",
            "player.snapshotSaved": "Screenshot saved to Photos",
            "player.snapshotFailed": "Could not save screenshot (Photos permission denied)",
            "player.infoTitle": "SWF information",
            "player.infoDimensions": "Stage size: %@ × %@",
            "player.infoFrameRate": "Frame rate: %@ fps",
            "player.infoFrames": "Total frames: %@",
            "player.infoSwfVersion": "SWF version: %@",
            "player.infoAS3": "ActionScript: %@",
            "player.infoAS3Value": "3.0",
            "player.infoAS12Value": "1.0 / 2.0",
            "player.infoUnknown": "unknown",
            "player.infoFileSize": "File size: %@"
        ],
        .zhHans: [
            "common.ok": "好",
            "common.cancel": "取消",
            "common.delete": "删除",
            "common.error": "出错了",
            "home.brandSub": "经典红白 · 专业播放",
            "home.freeBadge": "全功能免费 · 无次数限制",
            "home.importTitle": "选择本地 SWF 文件",
            "home.importSub": "重温经典 Flash 动画",
            "home.recent": "最近播放",
            "home.emptyTitle": "还没有导入 SWF 文件",
            "home.emptyHint": "点击上方红色卡片导入，或通过 Finder / iTunes 把 .swf 文件放进应用的文稿目录。",
            "home.lastPlayed": "上次播放：%@",
            "home.neverPlayed": "尚未播放",
            "home.deleteAction": "移除",
            "home.deleteConfirmTitle": "移除这个文件？",
            "home.deleteConfirmMessage": "导入的 SWF 文件将从本机删除。",
            "home.importErrorTitle": "导入失败",
            "home.importErrorUnsupported": "仅支持 .swf 文件。",
            "home.importErrorInvalid": "这不是有效的 SWF 文件（缺少 FWS / CWS / ZWS 文件头）。",
            "home.importErrorGeneric": "无法读取所选文件。",
            "home.shareAction": "分享",
            "settings.title": "设置",
            "settings.done": "完成",
            "settings.sectionLanguage": "语言 / Language",
            "settings.languageHint": "立即生效，无需重启应用。",
            "settings.sectionAbout": "关于本版本",
            "settings.sectionData": "数据",
            "settings.aboutText": "本版本是参照原版界面与功能所做的独立重写实现，使用 Ruffle 模拟器渲染 SWF。没有 VIP 等级、没有播放次数计数、没有内购、没有广告，也不需要联网。",
            "settings.version": "版本",
            "settings.edition": "版本类型",
            "settings.engine": "渲染引擎：Ruffle %@",
            "settings.noLimits": "功能限制：无",
            "settings.license": "开源许可",
            "settings.licenseText": "Ruffle 采用 MIT OR Apache-2.0 双许可，完整许可文本已随应用打包在 Web/LICENSE_MIT 与 Web/LICENSE_APACHE。",
            "settings.clearHistory": "清空播放记录",
            "settings.clearHistoryTitle": "清空所有导入文件？",
            "settings.clearHistoryMessage": "所有导入的 SWF 文件与封面缓存都会被删除。",
            "settings.clearAction": "全部清空",
            "player.loading": "正在加载 SWF…",
            "player.loadFailedTitle": "无法播放该 SWF",
            "player.loadFailedMessage": "Ruffle 引擎无法加载此文件，可能使用了尚不支持的 ActionScript 特性。",
            "player.engineMissing": "当前构建缺少 Ruffle 引擎资源，构建前请先执行 Scripts/fetch-ruffle.sh。",
            "player.retryAction": "重试",
            "player.back": "返回",
            "player.mute": "静音",
            "player.unmute": "取消静音",
            "player.snapshot": "截图",
            "player.info": "文件信息",
            "player.fullscreen": "全屏",
            "player.exitFullscreen": "退出全屏",
            "player.restart": "重新播放",
            "player.play": "播放",
            "player.pause": "暂停",
            "player.snapshotSaved": "截图已保存到相册",
            "player.snapshotFailed": "截图保存失败（无相册权限）",
            "player.infoTitle": "SWF 文件信息",
            "player.infoDimensions": "舞台尺寸：%@ × %@",
            "player.infoFrameRate": "帧率：%@ fps",
            "player.infoFrames": "总帧数：%@",
            "player.infoSwfVersion": "SWF 版本：%@",
            "player.infoAS3": "ActionScript：%@",
            "player.infoAS3Value": "3.0",
            "player.infoAS12Value": "1.0 / 2.0",
            "player.infoUnknown": "未知",
            "player.infoFileSize": "文件大小：%@"
        ],
        .ja: [
            "common.ok": "OK",
            "common.cancel": "キャンセル",
            "common.delete": "削除",
            "common.error": "エラー",
            "home.brandSub": "クラシックな赤と白 · プロ再生",
            "home.freeBadge": "全機能無料 · 回数制限なし",
            "home.importTitle": "ローカル SWF ファイルを選択",
            "home.importSub": "Flash の思い出をもう一度",
            "home.recent": "最近再生した項目",
            "home.emptyTitle": "SWF ファイルがありません",
            "home.emptyHint": "上の赤いカードから読み込むか、Finder / iTunes で .swf をアプリの書類フォルダに追加してください。",
            "home.lastPlayed": "最終再生: %@",
            "home.neverPlayed": "未再生",
            "home.deleteAction": "削除",
            "home.deleteConfirmTitle": "このファイルを削除しますか？",
            "home.deleteConfirmMessage": "読み込んだ SWF ファイルが端末から削除されます。",
            "home.importErrorTitle": "読み込みに失敗しました",
            "home.importErrorUnsupported": ".swf ファイルのみ対応しています。",
            "home.importErrorInvalid": "有効な SWF ファイルではありません（FWS / CWS / ZWS ヘッダーがありません）。",
            "home.importErrorGeneric": "選択したファイルを読み込めませんでした。",
            "home.shareAction": "共有",
            "settings.title": "設定",
            "settings.done": "完了",
            "settings.sectionLanguage": "言語 / Language",
            "settings.languageHint": "すぐに反映されます。再起動は不要です。",
            "settings.sectionAbout": "このビルドについて",
            "settings.sectionData": "データ",
            "settings.aboutText": "オリジナルの SWF Player の画面と機能を参考にした独立した再実装です。描画には Ruffle エミュレータを使用しています。VIP 区分、再生回数カウンター、アプリ内課金、広告、ネットワーク通信は一切ありません。",
            "settings.version": "バージョン",
            "settings.edition": "エディション",
            "settings.engine": "描画エンジン: Ruffle %@",
            "settings.noLimits": "機能制限: なし",
            "settings.license": "オープンソースライセンス",
            "settings.licenseText": "Ruffle は MIT OR Apache-2.0 のデュアルライセンスです。全文はアプリ内の Web/LICENSE_MIT と Web/LICENSE_APACHE に同梱されています。",
            "settings.clearHistory": "再生履歴を消去",
            "settings.clearHistoryTitle": "読み込んだファイルを全て消去しますか？",
            "settings.clearHistoryMessage": "SWF ファイルとカバー画像のキャッシュがすべて削除されます。",
            "settings.clearAction": "すべて消去",
            "player.loading": "SWF を読み込み中…",
            "player.loadFailedTitle": "この SWF を再生できません",
            "player.loadFailedMessage": "Ruffle エンジンがファイルを読み込めませんでした。未対応の ActionScript 機能を使っている可能性があります。",
            "player.engineMissing": "このビルドには Ruffle エンジンが同梱されていません。ビルド前に Scripts/fetch-ruffle.sh を実行してください。",
            "player.retryAction": "再試行",
            "player.back": "戻る",
            "player.mute": "ミュート",
            "player.unmute": "ミュート解除",
            "player.snapshot": "スクリーンショット",
            "player.info": "ファイル情報",
            "player.fullscreen": "全画面",
            "player.exitFullscreen": "全画面を終了",
            "player.restart": "最初から再生",
            "player.play": "再生",
            "player.pause": "一時停止",
            "player.snapshotSaved": "スクリーンショットを写真に保存しました",
            "player.snapshotFailed": "スクリーンショットを保存できませんでした（写真へのアクセスが許可されていません）",
            "player.infoTitle": "SWF 情報",
            "player.infoDimensions": "ステージサイズ: %@ × %@",
            "player.infoFrameRate": "フレームレート: %@ fps",
            "player.infoFrames": "総フレーム数: %@",
            "player.infoSwfVersion": "SWF バージョン: %@",
            "player.infoAS3": "ActionScript: %@",
            "player.infoAS3Value": "3.0",
            "player.infoAS12Value": "1.0 / 2.0",
            "player.infoUnknown": "不明",
            "player.infoFileSize": "ファイルサイズ: %@"
        ]
    ]
}

/// 便捷取词。`%@` 等格式化占位符只在传入参数时才参与 String(format:)。
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.shared.t(key)
    guard !args.isEmpty else { return format }
    return String(format: format, arguments: args)
}
