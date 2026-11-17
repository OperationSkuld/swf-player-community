import Foundation

/// 应用内语言偏好。`.system` 跟随系统，其余为用户强制指定的语言。
enum AppLanguage: String, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case ja
    case en

    var displayName: String {
        switch self {
        case .system:
            switch L10n.shared.effective {
            case .zhHans: return "跟随系统"
            case .ja: return "システムに従う"
            default: return "Follow System"
            }
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
            "home.brandSub": "Community Edition",
            "home.importTitle": "Open SWF File",
            "home.importSub": "Select and play Flash animation or game",
            "home.recent": "Recent Plays",
            "home.emptyTitle": "No SWF files yet",
            "home.emptyHint": "Tap the red card to import a local .swf, or use Open Web Page to browse a site and run any Flash resources it contains.",
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
            "home.openURL": "Open Web Page",
            "home.urlTitle": "Open Web Page",
            "home.urlMessage": "Enter any web address. It opens in the built-in browser; Flash resources found on the page can be downloaded and played locally.",
            "home.urlPlaceholder": "https://example.com",
            "home.urlLoad": "Open",
            "home.urlLoading": "Opening…",
            "home.urlInvalid": "Please enter a valid http or https link.",
            "home.urlFailedTitle": "Could not load",
            "home.urlHTTPError": "The server returned HTTP %@.",
            "home.urlNotSWF": "This link does not point to a .swf file.",
            "home.urlTooLarge": "This file is larger than 60 MB.",
            "browser.title": "Browser",
            "browser.close": "Close",
            "browser.back": "Back",
            "browser.forward": "Forward",
            "browser.reload": "Reload",
            "browser.addressPlaceholder": "Enter address or search",
            "browser.swfCount": "Flash %@",
            "browser.swfNoneShort": "Flash",
            "browser.swfListTitle": "Flash resources on this page",
            "browser.swfListMessage": "Found %@ SWF resource(s). Choose one to download and play locally.",
            "browser.swfNone": "No Flash resources were detected on this page. Scroll or reload and try again.",
            "browser.directSWFTitle": "Flash file detected",
            "browser.directSWFMessage": "This link points to a SWF file. Download it to play in the built-in player?\n%@",
            "browser.downloadAction": "Download & Play",
            "browser.downloading": "Downloading SWF…",
            "browser.httpError": "The server returned HTTP %@.",
            "browser.invalidSWF": "This is not a valid SWF file (missing FWS / CWS / ZWS header).",
            "browser.tooLarge": "This file is larger than 60 MB.",
            "browser.loadFailedTitle": "Could not load",
            "browser.sniffHint": "Browsing in the built-in browser. Tap the Flash badge to run any detected SWF locally.",
            "settings.title": "Settings",
            "settings.sectionPlayer": "PLAYER PREFERENCES",
            "settings.autoPlay": "Auto-play",
            "settings.autoPlaySub": "Start SWF immediately upon load",
            "settings.startMuted": "Start Muted",
            "settings.startMutedSub": "Disable audio by default when playing",
            "settings.sectionData": "DATA & STORAGE",
            "settings.clearHistory": "Clear History & Cache",
            "settings.clearHistorySub": "Remove play records & free space (%@)",
            "settings.clearHistoryTitle": "Clear all imported files?",
            "settings.clearHistoryMessage": "All imported SWF files and cached covers will be removed.",
            "settings.clearAction": "Clear all",
            "settings.sectionAbout": "ABOUT",
            "settings.languageRow": "Language",
            "settings.version": "Version",
            "settings.engineRow": "Engine",
            "player.loading": "Loading SWF…",
            "player.loadFailedTitle": "Could not play this SWF",
            "player.runtimeHint": "The built-in Flash engine could not render this file. Try again, or the animation may rely on features that are not supported yet.",
            "player.retryAction": "Retry",
            "player.back": "Back",
            "player.rotate": "Rotate screen",
            "player.reload": "Reload",
            "player.brightness": "Brightness",
            "player.volume": "Volume",
            "player.mute": "Mute",
            "player.unmute": "Unmute",
            "player.snapshot": "Screenshot",
            "player.info": "File info",
            "player.infoTitle": "SWF information",
            "player.infoClose": "Close",
            "player.play": "Play",
            "player.pause": "Pause",
            "player.snapshotSaved": "Screenshot saved to Photos",
            "player.snapshotFailed": "Could not save screenshot (Photos permission denied)",
            "player.infoDimensions": "Stage size: %@ × %@",
            "player.infoFrameRate": "Frame rate: %@ fps",
            "player.infoFrames": "Total frames: %@",
            "player.infoSwfVersion": "SWF version: %@",
            "player.infoAS3": "ActionScript: %@",
            "player.infoAS3Value": "3.0",
            "player.infoAS12Value": "1.0 / 2.0",
            "player.infoUnknown": "unknown",
            "player.infoFileSize": "File size: %@",
            "player.quality": "HQ mode",
            "player.qualityOn": "HQ mode on · reloading at full quality",
            "player.qualityOff": "HQ mode off · reloading for speed",
            "player.stretch": "Stretch to fill",
            "player.stretchOn": "Stretched to fill the screen",
            "player.stretchOff": "Original aspect ratio restored",
            "player.textSize": "Text size",
            "player.textSmall": "Small",
            "player.textStandard": "Standard",
            "player.textLarge": "Large",
            "player.textApplied": "Text size: %@"
        ],
        .zhHans: [
            "common.ok": "好",
            "common.cancel": "取消",
            "common.delete": "删除",
            "common.error": "出错了",
            "home.brandSub": "社区版",
            "home.importTitle": "打开 SWF 文件",
            "home.importSub": "选择并播放 Flash 动画或游戏",
            "home.recent": "最近播放",
            "home.emptyTitle": "还没有导入 SWF 文件",
            "home.emptyHint": "点击上方红色卡片导入本地文件，或用「打开网页」在内置浏览器中访问网站并运行其中的 Flash 资源。",
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
            "home.openURL": "打开网页",
            "home.urlTitle": "打开网页",
            "home.urlMessage": "输入任意网址，将在内置浏览器中打开。若网页含 Flash 资源，可下载到本地播放。",
            "home.urlPlaceholder": "https://example.com",
            "home.urlLoad": "打开",
            "home.urlLoading": "正在打开…",
            "home.urlInvalid": "请输入有效的 http 或 https 链接。",
            "home.urlFailedTitle": "加载失败",
            "home.urlHTTPError": "服务器返回了 HTTP %@。",
            "home.urlNotSWF": "这个链接不是 .swf 文件。",
            "home.urlTooLarge": "文件超过 60 MB，暂不支持。",
            "browser.title": "浏览器",
            "browser.close": "关闭",
            "browser.back": "后退",
            "browser.forward": "前进",
            "browser.reload": "刷新",
            "browser.addressPlaceholder": "输入网址或搜索",
            "browser.swfCount": "Flash %@",
            "browser.swfNoneShort": "Flash",
            "browser.swfListTitle": "本页 Flash 资源",
            "browser.swfListMessage": "发现 %@ 个 SWF 资源，选择一项下载到本地播放。",
            "browser.swfNone": "当前页面未检测到 Flash 资源。可滚动或刷新后再试。",
            "browser.directSWFTitle": "检测到 Flash 文件",
            "browser.directSWFMessage": "该链接指向 SWF 文件，是否下载到本地播放？\n%@",
            "browser.downloadAction": "下载并播放",
            "browser.downloading": "正在下载 SWF…",
            "browser.httpError": "服务器返回了 HTTP %@。",
            "browser.invalidSWF": "这不是有效的 SWF 文件（缺少 FWS / CWS / ZWS 文件头）。",
            "browser.tooLarge": "文件超过 60 MB，暂不支持。",
            "browser.loadFailedTitle": "加载失败",
            "browser.sniffHint": "正在内置浏览器中浏览。检测到 Flash 资源后，点右上角按钮即可在本地运行。",
            "settings.title": "设置",
            "settings.sectionPlayer": "播放偏好",
            "settings.autoPlay": "自动播放",
            "settings.autoPlaySub": "载入后立即开始播放",
            "settings.startMuted": "启动静音",
            "settings.startMutedSub": "播放时默认关闭声音",
            "settings.sectionData": "数据与存储",
            "settings.clearHistory": "清除历史与缓存",
            "settings.clearHistorySub": "清除播放记录并释放空间（%@）",
            "settings.clearHistoryTitle": "清空所有导入文件？",
            "settings.clearHistoryMessage": "所有导入的 SWF 文件与封面缓存都会被删除。",
            "settings.clearAction": "全部清空",
            "settings.sectionAbout": "关于",
            "settings.languageRow": "语言",
            "settings.version": "版本",
            "settings.engineRow": "渲染引擎",
            "player.loading": "正在加载 SWF…",
            "player.loadFailedTitle": "无法播放该 SWF",
            "player.runtimeHint": "内置 Flash 引擎无法渲染此文件。可以重试，也可能是该动画使用了暂不支持的特性。",
            "player.retryAction": "重试",
            "player.back": "返回",
            "player.rotate": "横竖屏切换",
            "player.reload": "重载",
            "player.brightness": "亮度",
            "player.volume": "音量",
            "player.mute": "静音",
            "player.unmute": "取消静音",
            "player.snapshot": "截图",
            "player.info": "播放详情",
            "player.infoTitle": "SWF 播放详情",
            "player.infoClose": "关闭",
            "player.play": "播放",
            "player.pause": "暂停",
            "player.snapshotSaved": "截图已保存到相册",
            "player.snapshotFailed": "截图保存失败（无相册权限）",
            "player.infoDimensions": "舞台尺寸：%@ × %@",
            "player.infoFrameRate": "帧率：%@ fps",
            "player.infoFrames": "总帧数：%@",
            "player.infoSwfVersion": "SWF 版本：%@",
            "player.infoAS3": "ActionScript：%@",
            "player.infoAS3Value": "3.0",
            "player.infoAS12Value": "1.0 / 2.0",
            "player.infoUnknown": "未知",
            "player.infoFileSize": "文件大小：%@",
            "player.quality": "HQ 模式",
            "player.qualityOn": "HQ 模式已开启 · 正以高画质重载",
            "player.qualityOff": "HQ 模式已关闭 · 正以流畅优先重载",
            "player.stretch": "平铺",
            "player.stretchOn": "已平铺铺满屏幕",
            "player.stretchOff": "已恢复原始比例",
            "player.textSize": "字体",
            "player.textSmall": "小",
            "player.textStandard": "标准",
            "player.textLarge": "大",
            "player.textApplied": "字体大小：%@"
        ],
        .ja: [
            "common.ok": "OK",
            "common.cancel": "キャンセル",
            "common.delete": "削除",
            "common.error": "エラー",
            "home.brandSub": "コミュニティ版",
            "home.importTitle": "SWF ファイルを開く",
            "home.importSub": "Flash アニメやゲームを選んで再生",
            "home.recent": "最近再生",
            "home.emptyTitle": "SWF ファイルがありません",
            "home.emptyHint": "上の赤いカードからローカルファイルを読み込むか、「Web ページを開く」で内蔵ブラウザーから Flash リソースを再生できます。",
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
            "home.openURL": "Web ページを開く",
            "home.urlTitle": "Web ページを開く",
            "home.urlMessage": "任意のアドレスを入力すると内蔵ブラウザーで開きます。ページ内の Flash リソースはダウンロードして再生できます。",
            "home.urlPlaceholder": "https://example.com",
            "home.urlLoad": "開く",
            "home.urlLoading": "開いています…",
            "home.urlInvalid": "有効な http / https リンクを入力してください。",
            "home.urlFailedTitle": "読み込めませんでした",
            "home.urlHTTPError": "サーバーが HTTP %@ を返しました。",
            "home.urlNotSWF": "このリンクは .swf ファイルではありません。",
            "home.urlTooLarge": "ファイルが 60 MB を超えています。",
            "browser.title": "ブラウザー",
            "browser.close": "閉じる",
            "browser.back": "戻る",
            "browser.forward": "進む",
            "browser.reload": "再読み込み",
            "browser.addressPlaceholder": "アドレスまたは検索語を入力",
            "browser.swfCount": "Flash %@",
            "browser.swfNoneShort": "Flash",
            "browser.swfListTitle": "このページの Flash リソース",
            "browser.swfListMessage": "%@ 個の SWF リソースが見つかりました。ダウンロードして再生するものを選んでください。",
            "browser.swfNone": "Flash リソースは検出されませんでした。スクロールまたは再読み込みしてお試しください。",
            "browser.directSWFTitle": "Flash ファイルを検出",
            "browser.directSWFMessage": "このリンクは SWF ファイルです。ダウンロードして内蔵プレイヤーで再生しますか？\n%@",
            "browser.downloadAction": "ダウンロードして再生",
            "browser.downloading": "SWF をダウンロード中…",
            "browser.httpError": "サーバーが HTTP %@ を返しました。",
            "browser.invalidSWF": "有効な SWF ファイルではありません（FWS / CWS / ZWS ヘッダーがありません）。",
            "browser.tooLarge": "ファイルが 60 MB を超えています。",
            "browser.loadFailedTitle": "読み込めませんでした",
            "browser.sniffHint": "内蔵ブラウザーで閲覧中です。Flash を検出したら右上のボタンからローカルで再生できます。",
            "settings.title": "設定",
            "settings.sectionPlayer": "再生設定",
            "settings.autoPlay": "自動再生",
            "settings.autoPlaySub": "読み込み後すぐに再生を開始",
            "settings.startMuted": "起動時ミュート",
            "settings.startMutedSub": "再生時にデフォルトで消音",
            "settings.sectionData": "データとストレージ",
            "settings.clearHistory": "履歴とキャッシュを消去",
            "settings.clearHistorySub": "再生履歴を消去して空き容量を確保（%@）",
            "settings.clearHistoryTitle": "読み込んだファイルを全て消去しますか？",
            "settings.clearHistoryMessage": "SWF ファイルとカバー画像のキャッシュがすべて削除されます。",
            "settings.clearAction": "すべて消去",
            "settings.sectionAbout": "このアプリについて",
            "settings.languageRow": "言語",
            "settings.version": "バージョン",
            "settings.engineRow": "描画エンジン",
            "player.loading": "SWF を読み込み中…",
            "player.loadFailedTitle": "この SWF を再生できません",
            "player.runtimeHint": "内蔵 Flash エンジンがこのファイルを描画できませんでした。再試行するか、未対応の機能を使っている可能性があります。",
            "player.retryAction": "再試行",
            "player.back": "戻る",
            "player.rotate": "画面の向き",
            "player.reload": "再読み込み",
            "player.brightness": "明るさ",
            "player.volume": "音量",
            "player.mute": "ミュート",
            "player.unmute": "ミュート解除",
            "player.snapshot": "スクリーンショット",
            "player.info": "再生情報",
            "player.infoTitle": "SWF 再生情報",
            "player.infoClose": "閉じる",
            "player.play": "再生",
            "player.pause": "一時停止",
            "player.snapshotSaved": "スクリーンショットを写真に保存しました",
            "player.snapshotFailed": "スクリーンショットを保存できませんでした（写真へのアクセスが許可されていません）",
            "player.infoDimensions": "ステージサイズ: %@ × %@",
            "player.infoFrameRate": "フレームレート: %@ fps",
            "player.infoFrames": "総フレーム数: %@",
            "player.infoSwfVersion": "SWF バージョン: %@",
            "player.infoAS3": "ActionScript: %@",
            "player.infoAS3Value": "3.0",
            "player.infoAS12Value": "1.0 / 2.0",
            "player.infoUnknown": "不明",
            "player.infoFileSize": "ファイルサイズ: %@",
            "player.quality": "HQ モード",
            "player.qualityOn": "HQ モード ON · 高画質で再読み込み中",
            "player.qualityOff": "HQ モード OFF · 速度優先で再読み込み中",
            "player.stretch": "画面いっぱい",
            "player.stretchOn": "画面いっぱいに拡大しました",
            "player.stretchOff": "元の縦横比に戻しました",
            "player.textSize": "文字サイズ",
            "player.textSmall": "小",
            "player.textStandard": "標準",
            "player.textLarge": "大",
            "player.textApplied": "文字サイズ: %@"
        ]
    ]
}

/// 便捷取词。`%@` 等格式化占位符只在传入参数时才参与 String(format:)。
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.shared.t(key)
    guard !args.isEmpty else { return format }
    return String(format: format, arguments: args)
}
