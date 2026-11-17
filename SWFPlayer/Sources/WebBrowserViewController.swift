import UIKit
import WebKit

/// 内置网页浏览器：直接访问网址，嗅探页面中的 Flash(SWF) 资源，下载到本地播放。
///
/// 设计取舍：
///  - 第三方网页内部直接注入 Ruffle 不可靠（跨域/CSP/WASM publicPath），
///    因此采用「网页照常展示 → 嗅探 .swf → 下载 → 本地 PlayerViewController 播放」。
///  - 支持多窗口（标签页）：每个窗口一个独立 WKWebView，可新建/切换/关闭。
///  - 历史按主域名（eTLD+1）去重，宫格展示 favicon + 站点名。
final class WebBrowserViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler,
                                     UITextFieldDelegate, UICollectionViewDataSource, UICollectionViewDelegate {

    // MARK: - 标签页模型

    private final class Tab {
        let id = UUID()
        let webView: WKWebView
        var title: String = ""
        var url: URL?
        var detectedSWFs: [String] = []
        var isStartPage: Bool = true

        init(configuration: WKWebViewConfiguration) {
            self.webView = WKWebView(frame: .zero, configuration: configuration)
        }
    }

    private var tabs: [Tab] = []
    private var currentIndex: Int = 0
    private var currentTab: Tab? { tabs.indices.contains(currentIndex) ? tabs[currentIndex] : nil }

    // MARK: - 工具栏

    private let closeButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let tabsButton = UIButton(type: .system)
    private let addressField = UITextField()
    /// Flash 角标：独立按钮，放在地址栏右侧外部，单行完整显示，不被挤压。
    private let swfButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)

    // MARK: - 标签切换面板

    private let tabsPanel = UIView()
    private let tabsPanelTitle = UILabel()
    private let tabsPanelNewButton = UIButton(type: .system)
    private let tabsPanelCloseButton = UIButton(type: .system)
    private let tabsCollection: UICollectionView
    private var tabsPanelVisible = false

    // MARK: - 起始页

    private let startPage = UIView()
    private let startIcon = UIImageView()
    private let startTitle = UILabel()
    private let startSubtitle = UILabel()
    private let tipCard = UIView()
    private let tipIcon = UIImageView()
    private let tipTitle = UILabel()
    private let tipBody = UILabel()
    private let historyTitle = UILabel()
    private let historyClearButton = UIButton(type: .system)
    private let historyGrid: UICollectionView

    // MARK: - 下载遮罩与提示

    private let busyOverlay = UIView()
    private let busyCard = UIView()
    private let busySpinner = UIActivityIndicatorView(style: .large)
    private let busyLabel = UILabel()
    private var toastLabel: UILabel?

    // MARK: - 历史与配置

    private struct HistoryEntry: Codable, Equatable {
        var url: String
        var title: String
        var favicon: String?
    }

    private static let historyKey = "community.swfplayer.browserHistoryV2"
    private static let historyLimit = 8
    private var history: [HistoryEntry] = []
    private var pageTitle: String = ""
    private var pageFavicon: String?
    private var didInitialAppearance = false

    private let webConfiguration: WKWebViewConfiguration

    // MARK: - 初始化

    init(url: URL?) {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.sniffScript,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: false)
        )
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webConfiguration = config

        let gridLayout = UICollectionViewFlowLayout()
        gridLayout.minimumLineSpacing = 14
        gridLayout.minimumInteritemSpacing = 12
        self.historyGrid = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)

        let tabsLayout = UICollectionViewFlowLayout()
        tabsLayout.scrollDirection = .horizontal
        tabsLayout.minimumLineSpacing = 12
        tabsLayout.itemSize = CGSize(width: 150, height: 190)
        self.tabsCollection = UICollectionView(frame: .zero, collectionViewLayout: tabsLayout)

        super.init(nibName: nil, bundle: nil)
        if let url = url {
            openInitial(url)
        } else {
            addTabAndSelect(load: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        webConfiguration.userContentController.removeScriptMessageHandler(forName: "swfSniff")
    }

    override var prefersStatusBarHidden: Bool { false }

    private func openInitial(_ url: URL) {
        addTabAndSelect(load: url)
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationController?.setNavigationBarHidden(true, animated: false)
        title = L("browser.title")

        webConfiguration.userContentController.add(
            WeakScriptMessageHandler(delegate: self), name: "swfSniff")

        buildToolbar()
        buildStartPage()
        buildTabsPanel()
        buildBusyOverlay()
        loadHistory()
        applyLocalization()
        attachCurrentWebView()
        updateUIForCurrentTab()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didInitialAppearance else { return }
        didInitialAppearance = true
        if currentTab?.isStartPage == true {
            addressField.becomeFirstResponder()
        }
    }

    // MARK: - 工具栏

    private func buildToolbar() {
        [closeButton, backButton, forwardButton, reloadButton, tabsButton].forEach {
            $0.tintColor = Theme.ink
            view.addSubview($0)
        }
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        tabsButton.addTarget(self, action: #selector(toggleTabsPanel), for: .touchUpInside)

        addressField.borderStyle = .roundedRect
        addressField.returnKeyType = .go
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.clearButtonMode = .whileEditing
        addressField.font = UIFont.systemFont(ofSize: 14)
        addressField.textColor = Theme.ink
        addressField.backgroundColor = Theme.groupedBackground
        addressField.delegate = self
        view.addSubview(addressField)

        // Flash 角标是独立按钮，不进地址栏；宽度固定，单行显示「⚡ N」，绝不挤压输入框。
        swfButton.addTarget(self, action: #selector(showDetectedSWFs), for: .touchUpInside)
        swfButton.titleLabel?.lineBreakMode = .byClipping
        view.addSubview(swfButton)

        activity.hidesWhenStopped = true
        activity.color = Theme.secondary
        view.addSubview(activity)
    }

    private func applyLocalization() {
        closeButton.accessibilityLabel = L("browser.close")
        backButton.accessibilityLabel = L("browser.back")
        forwardButton.accessibilityLabel = L("browser.forward")
        reloadButton.accessibilityLabel = L("browser.reload")
        tabsButton.accessibilityLabel = L("browser.tabs")
        addressField.placeholder = L("browser.addressPlaceholder")
        busyLabel.text = L("browser.downloading")
        startTitle.text = L("browser.startTitle")
        startSubtitle.text = L("browser.startSubtitle")
        tipTitle.text = L("browser.tipTitle")
        tipBody.text = L("browser.tipBody")
        historyTitle.text = L("browser.historyTitle")
        historyClearButton.setTitle(L("browser.historyClear"), for: .normal)
        tabsPanelTitle.text = L("browser.tabsTitle")
        tabsPanelNewButton.setTitle(L("browser.tabNew"), for: .normal)
        updateSWFBadge()
    }

    private func setButton(_ button: UIButton, symbol: String, pointSize: CGFloat = 15) {
        let image = UIImage(systemName: symbol,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
        button.setImage(image, for: .normal)
    }

    // MARK: - 布局

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let insets = view.safeAreaInsets
        let top = insets.top + 8
        let barHeight: CGFloat = 38
        let pad: CGFloat = 8
        let side: CGFloat = 30
        let gap: CGFloat = 2

        setButton(closeButton, symbol: "xmark", pointSize: 13)
        setButton(backButton, symbol: "chevron.left", pointSize: 15)
        setButton(forwardButton, symbol: "chevron.right", pointSize: 15)
        setButton(reloadButton, symbol: "arrow.clockwise", pointSize: 14)
        setButton(tabsButton, symbol: "square.on.square", pointSize: 14)

        closeButton.frame = CGRect(x: pad, y: top, width: side, height: barHeight)
        backButton.frame = CGRect(x: closeButton.frame.maxX + gap, y: top, width: side, height: barHeight)
        forwardButton.frame = CGRect(x: backButton.frame.maxX + gap, y: top, width: side, height: barHeight)

        // 右侧：多窗口按钮 + Flash 角标 + 刷新，均独立成行，互不重叠。
        reloadButton.frame = CGRect(x: width - pad - side, y: top, width: side, height: barHeight)
        let badgeW: CGFloat = 56
        swfButton.frame = CGRect(x: reloadButton.frame.minX - badgeW - gap,
                                 y: top, width: badgeW, height: barHeight)
        tabsButton.frame = CGRect(x: swfButton.frame.minX - side - gap,
                                  y: top, width: side, height: barHeight)
        updateTabsBadge()

        // 地址栏占满前进按钮与多窗口按钮之间的宽度，右侧不塞任何东西。
        let fieldX = forwardButton.frame.maxX + 6
        let fieldW = max(80, tabsButton.frame.minX - 6 - fieldX)
        addressField.frame = CGRect(x: fieldX, y: top, width: fieldW, height: barHeight)
        activity.frame = CGRect(x: addressField.frame.maxX - 26,
                                y: top + (barHeight - 18) / 2, width: 18, height: 18)

        let webTop = top + barHeight + 8
        for tab in tabs {
            tab.webView.frame = CGRect(x: 0, y: webTop, width: width, height: view.bounds.height - webTop)
        }

        busyOverlay.frame = view.bounds
        let cardSize = CGSize(width: 168, height: 116)
        busyCard.frame = CGRect(x: (width - cardSize.width) / 2,
                                y: (view.bounds.height - cardSize.height) / 2,
                                width: cardSize.width, height: cardSize.height)
        busySpinner.frame = CGRect(x: (cardSize.width - 34) / 2, y: 20, width: 34, height: 34)
        busyLabel.frame = CGRect(x: 10, y: 64, width: cardSize.width - 20, height: 34)

        layoutStartPage(webTop: webTop)
        layoutTabsPanel(webTop: webTop)
    }

    // MARK: - 标签页管理

    @discardableResult
    private func addTabAndSelect(load url: URL?) -> Tab {
        let tab = Tab(configuration: webConfiguration)
        tab.webView.navigationDelegate = self
        tab.webView.allowsBackForwardNavigationGestures = true
        tab.webView.scrollView.contentInsetAdjustmentBehavior = .never
        tab.webView.backgroundColor = Theme.background
        tabs.append(tab)
        currentIndex = tabs.count - 1
        if let url = url {
            tab.url = url
            tab.isStartPage = false
            tab.webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        } else {
            tab.webView.load(URLRequest(url: URL(string: "about:blank")!))
        }
        if isViewLoaded { attachCurrentWebView(); updateUIForCurrentTab() }
        return tab
    }

    private func attachCurrentWebView() {
        guard let tab = currentTab else { return }
        for (index, t) in tabs.enumerated() {
            if index == currentIndex {
                if t.webView.superview !== view { view.insertSubview(t.webView, at: 0) }
                t.webView.isHidden = false
            } else {
                t.webView.removeFromSuperview()
            }
        }
        // 起始页盖在当前 webView 上（webView 在 layer 0）。
        view.insertSubview(startPage, aboveSubview: tab.webView)
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index), tabs.count > 1 else { return }
        let tab = tabs[index]
        // message handler 挂在共享 configuration 上，不能按 tab 移除，否则影响其它窗口。
        tab.webView.removeFromSuperview()
        tabs.remove(at: index)
        if currentIndex >= tabs.count { currentIndex = tabs.count - 1 }
        else if index < currentIndex { currentIndex -= 1 }
        attachCurrentWebView()
        updateUIForCurrentTab()
        tabsCollection.reloadData()
    }

    private func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        currentIndex = index
        hideTabsPanel()
        attachCurrentWebView()
        updateUIForCurrentTab()
    }

    private func updateUIForCurrentTab() {
        guard let tab = currentTab else { return }
        addressField.text = tab.url?.absoluteString
        startPage.isHidden = !tab.isStartPage
        if tab.isStartPage { addressField.text = nil }
        updateNavButtons()
        updateSWFBadge()
        updateTabsBadge()
        historyGrid.reloadData()
        tabsCollection.reloadData()
    }

    private func updateTabsBadge() {
        let count = max(1, tabs.count)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "square.on.square",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        var title = AttributedString(String(count))
        title.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        config.attributedTitle = title
        config.imagePadding = 2
        config.baseForegroundColor = Theme.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        tabsButton.configuration = config
    }

    // MARK: - 标签切换面板

    private func buildTabsPanel() {
        tabsPanel.isHidden = true
        tabsPanel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let tap = UITapGestureRecognizer(target: self, action: #selector(hideTabsPanel))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        tabsPanel.addGestureRecognizer(tap)
        view.addSubview(tabsPanel)

        let panel = UIView()
        panel.backgroundColor = Theme.background
        panel.layer.cornerRadius = 18
        panel.clipsToBounds = true
        panel.tag = 901
        tabsPanel.addSubview(panel)

        tabsPanelTitle.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        tabsPanelTitle.textColor = Theme.ink
        panel.addSubview(tabsPanelTitle)

        tabsPanelNewButton.setTitleColor(Theme.red, for: .normal)
        tabsPanelNewButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        tabsPanelNewButton.addTarget(self, action: #selector(newTabFromPanel), for: .touchUpInside)
        panel.addSubview(tabsPanelNewButton)

        tabsPanelCloseButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        tabsPanelCloseButton.tintColor = Theme.secondary
        tabsPanelCloseButton.addTarget(self, action: #selector(hideTabsPanel), for: .touchUpInside)
        panel.addSubview(tabsPanelCloseButton)

        tabsCollection.backgroundColor = .clear
        tabsCollection.dataSource = self
        tabsCollection.delegate = self
        tabsCollection.register(TabCell.self, forCellWithReuseIdentifier: "TabCell")
        tabsCollection.alwaysBounceHorizontal = true
        panel.addSubview(tabsCollection)
    }

    private func layoutTabsPanel(webTop: CGFloat) {
        tabsPanel.frame = view.bounds
        let panelH: CGFloat = 300
        guard let panel = tabsPanel.viewWithTag(901) else { return }
        panel.frame = CGRect(x: 12, y: webTop + 24, width: view.bounds.width - 24, height: panelH)
        tabsPanelTitle.frame = CGRect(x: 18, y: 14, width: 200, height: 28)
        tabsPanelCloseButton.frame = CGRect(x: panel.bounds.width - 44, y: 14, width: 30, height: 30)
        tabsPanelNewButton.frame = CGRect(x: panel.bounds.width - 110, y: 18, width: 60, height: 24)
        tabsCollection.frame = CGRect(x: 12, y: 52, width: panel.bounds.width - 24, height: panelH - 64)
    }

    @objc private func toggleTabsPanel() {
        tabsPanelVisible ? hideTabsPanel() : showTabsPanel()
    }

    private func showTabsPanel() {
        tabsPanelVisible = true
        tabsPanel.isHidden = false
        tabsCollection.reloadData()
        view.bringSubviewToFront(tabsPanel)
    }

    @objc private func hideTabsPanel() {
        tabsPanelVisible = false
        tabsPanel.isHidden = true
        addressField.resignFirstResponder()
    }

    @objc private func newTabFromPanel() {
        addTabAndSelect(load: nil)
        hideTabsPanel()
        addressField.becomeFirstResponder()
    }

    // 标签页 cell
    private final class TabCell: UICollectionViewCell {
        let titleLabel = UILabel()
        let hostLabel = UILabel()
        let closeBtn = UIButton(type: .system)
        let favicon = UIImageView()
        var onClose: (() -> Void)?
        var index: Int = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.backgroundColor = Theme.groupedBackground
            contentView.layer.cornerRadius = 12
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = Theme.hairline.cgColor
            contentView.clipsToBounds = true

            favicon.frame = CGRect(x: 12, y: 14, width: 28, height: 28)
            favicon.contentMode = .scaleAspectFit
            favicon.tintColor = Theme.red
            favicon.image = UIImage(systemName: "globe.americas.fill")
            contentView.addSubview(favicon)

            closeBtn.frame = CGRect(x: frame.width - 36, y: 10, width: 26, height: 26)
            closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            closeBtn.tintColor = Theme.secondary
            contentView.addSubview(closeBtn)

            hostLabel.frame = CGRect(x: 12, y: 56, width: frame.width - 24, height: 18)
            hostLabel.font = UIFont.systemFont(ofSize: 11)
            hostLabel.textColor = Theme.secondary
            hostLabel.lineBreakMode = .byTruncatingTail
            contentView.addSubview(hostLabel)

            titleLabel.frame = CGRect(x: 12, y: 76, width: frame.width - 24, height: 100)
            titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = Theme.ink
            titleLabel.numberOfLines = 5
            contentView.addSubview(titleLabel)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            closeBtn.frame = CGRect(x: contentView.bounds.width - 36, y: 10, width: 26, height: 26)
        }
    }

    // MARK: - 起始页

    private func buildStartPage() {
        startPage.backgroundColor = Theme.background
        view.addSubview(startPage)

        startIcon.image = UIImage(systemName: "globe.americas.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold))
        startIcon.tintColor = .white
        startIcon.contentMode = .center
        startIcon.backgroundColor = Theme.red
        startIcon.layer.cornerRadius = 18
        startIcon.clipsToBounds = true
        startPage.addSubview(startIcon)

        startTitle.font = UIFont.systemFont(ofSize: 22, weight: .heavy)
        startTitle.textColor = Theme.ink
        startTitle.textAlignment = .center
        startPage.addSubview(startTitle)

        startSubtitle.font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        startSubtitle.textColor = Theme.secondary
        startSubtitle.textAlignment = .center
        startSubtitle.numberOfLines = 2
        startPage.addSubview(startSubtitle)

        tipCard.backgroundColor = Theme.softRed
        tipCard.layer.cornerRadius = 16
        startPage.addSubview(tipCard)

        tipIcon.image = UIImage(systemName: "bolt.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        tipIcon.tintColor = Theme.red
        tipIcon.contentMode = .center
        tipCard.addSubview(tipIcon)

        tipTitle.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        tipTitle.textColor = Theme.ink
        tipCard.addSubview(tipTitle)

        tipBody.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        tipBody.textColor = Theme.secondary
        tipBody.numberOfLines = 3
        tipCard.addSubview(tipBody)

        historyTitle.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        historyTitle.textColor = Theme.ink
        startPage.addSubview(historyTitle)

        historyClearButton.setTitleColor(Theme.red, for: .normal)
        historyClearButton.titleLabel?.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        historyClearButton.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
        startPage.addSubview(historyClearButton)

        historyGrid.backgroundColor = .clear
        historyGrid.dataSource = self
        historyGrid.delegate = self
        historyGrid.register(HistoryCell.self, forCellWithReuseIdentifier: "HistoryCell")
        startPage.addSubview(historyGrid)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnStartPage))
        tap.cancelsTouchesInView = false
        startPage.addGestureRecognizer(tap)
    }

    private func layoutStartPage(webTop: CGFloat) {
        let width = view.bounds.width
        let height = view.bounds.height
        startPage.frame = CGRect(x: 0, y: webTop, width: width, height: height - webTop)
        let pad: CGFloat = 24
        let contentWidth = width - pad * 2

        startIcon.frame = CGRect(x: (width - 60) / 2, y: 24, width: 60, height: 60)
        startTitle.frame = CGRect(x: pad, y: 92, width: contentWidth, height: 30)
        startSubtitle.frame = CGRect(x: pad, y: 122, width: contentWidth, height: 38)

        let tipY: CGFloat = 168
        tipCard.frame = CGRect(x: pad, y: tipY, width: contentWidth, height: 84)
        tipIcon.frame = CGRect(x: 16, y: 14, width: 30, height: 30)
        tipTitle.frame = CGRect(x: 56, y: 14, width: contentWidth - 72, height: 22)
        tipBody.frame = CGRect(x: 56, y: 38, width: contentWidth - 72, height: 44)

        let histY = tipY + 84 + 20
        historyTitle.frame = CGRect(x: pad, y: histY, width: 180, height: 24)
        historyClearButton.frame = CGRect(x: width - pad - 60, y: histY, width: 60, height: 24)

        if let layout = historyGrid.collectionViewLayout as? UICollectionViewFlowLayout {
            let columns: CGFloat = 4
            let spacing: CGFloat = 12
            let cellW = floor((contentWidth - spacing * (columns - 1)) / columns)
            layout.itemSize = CGSize(width: cellW, height: 92)
            layout.minimumInteritemSpacing = spacing
            layout.minimumLineSpacing = 16
        }
        let gridY = histY + 32
        historyGrid.frame = CGRect(x: pad, y: gridY, width: contentWidth, height: max(0, height - webTop - gridY - 16))
    }

    @objc private func dismissKeyboardOnStartPage() {
        addressField.resignFirstResponder()
    }

    // 历史宫格 cell：favicon + 站点名
    private final class HistoryCell: UICollectionViewCell {
        let iconView = UIImageView()
        let nameLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.backgroundColor = Theme.card
            contentView.layer.cornerRadius = 12
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = Theme.hairline.cgColor
            contentView.clipsToBounds = true

            iconView.frame = CGRect(x: (frame.width - 38) / 2, y: 14, width: 38, height: 38)
            iconView.contentMode = .scaleAspectFit
            iconView.layer.cornerRadius = 9
            iconView.clipsToBounds = true
            iconView.backgroundColor = Theme.groupedBackground
            iconView.tintColor = Theme.red
            iconView.image = UIImage(systemName: "globe.americas.fill")
            contentView.addSubview(iconView)

            nameLabel.frame = CGRect(x: 6, y: 58, width: frame.width - 12, height: 28)
            nameLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
            nameLabel.textColor = Theme.ink
            nameLabel.textAlignment = .center
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.numberOfLines = 2
            contentView.addSubview(nameLabel)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func prepareForReuse() {
            super.prepareForReuse()
            iconView.image = UIImage(systemName: "globe.americas.fill")
            nameLabel.text = nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            iconView.frame = CGRect(x: (contentView.bounds.width - 38) / 2, y: 12, width: 38, height: 38)
            nameLabel.frame = CGRect(x: 6, y: 56, width: contentView.bounds.width - 12, height: 30)
        }
    }

    // MARK: - 历史记录（主域名去重，最多 8 条）

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = list
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    /// 提取主域名 eTLD+1：对常见二级后缀做处理，否则取 host 末两段。
    private func registrableDomain(_ host: String) -> String {
        let lower = host.lowercased()
        let parts = lower.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return lower }
        let twoLevel = Set(["com.cn", "net.cn", "org.cn", "co.jp", "co.uk", "com.au", "com.tw", "com.hk", "co.kr"])
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if parts.count >= 3 && twoLevel.contains(lastTwo) {
            return parts.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    private func recordHistory(_ url: URL, title: String?, favicon: String?) {
        guard let host = url.host, !host.isEmpty else { return }
        let domain = registrableDomain(host)
        let schemeHost = "\(url.scheme ?? "https")://\(host)"
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = cleanTitle.isEmpty ? host : cleanTitle
        let entry = HistoryEntry(url: schemeHost, title: displayName, favicon: favicon)
        // 同一主域名只保留最新一条。
        history.removeAll { registrableDomain(URL(string: $0.url)?.host ?? "") == domain }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
        saveHistory()
        historyGrid.reloadData()
    }

    @objc private func clearHistory() {
        history.removeAll()
        saveHistory()
        historyGrid.reloadData()
    }

    // MARK: - 浏览器动作

    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func backTapped() {
        guard let web = currentTab?.webView else { return }
        if web.canGoBack { web.goBack() } else { closeTapped() }
    }

    @objc private func forwardTapped() {
        guard let web = currentTab?.webView, web.canGoForward else { return }
        web.goForward()
    }

    @objc private func reloadTapped() {
        currentTab?.webView.reload()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let raw = textField.text ?? ""
        guard let url = normalizedURL(raw) else {
            showError(L("home.urlInvalid"))
            return false
        }
        loadCurrentTab(url)
        return true
    }

    private func loadCurrentTab(_ url: URL) {
        guard let tab = currentTab else { return }
        tab.url = url
        tab.isStartPage = false
        startPage.isHidden = true
        tab.webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    private func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private func updateNavButtons() {
        guard let web = currentTab?.webView else { return }
        backButton.isEnabled = web.canGoBack
        forwardButton.isEnabled = web.canGoForward
        backButton.alpha = web.canGoBack ? 1 : 0.4
        forwardButton.alpha = web.canGoForward ? 1 : 0.4
    }

    private func updateSWFBadge() {
        let count = currentTab?.detectedSWFs.count ?? 0
        swfButton.isEnabled = count > 0
        swfButton.alpha = count > 0 ? 1 : 0.5
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = count > 0 ? Theme.red : Theme.secondary
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        var title = AttributedString(count > 0 ? "⚡\(count)" : "⚡")
        title.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        config.attributedTitle = title
        swfButton.configuration = config
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === currentTab?.webView else { return }
        activity.startAnimating()
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === currentTab?.webView else { return }
        activity.stopAnimating()
        guard let tab = currentTab else { return }
        if let url = webView.url, url.absoluteString != "about:blank" {
            tab.url = url
            tab.isStartPage = false
            addressField.text = url.absoluteString
            startPage.isHidden = true
            // 抓取页面标题与 favicon 后记录历史。
            webView.evaluateJavaScript(Self.pageMetaScript) { [weak self, weak tab] result, _ in
                guard let self = self, let tab = tab,
                      let dict = result as? [String: Any] else { return }
                let title = dict["title"] as? String
                let icon = dict["icon"] as? String
                DispatchQueue.main.async {
                    tab.title = title ?? (url.host ?? "")
                    self.recordHistory(url, title: title, favicon: icon)
                    self.tabsCollection.reloadData()
                }
            }
        } else if webView.url?.absoluteString == "about:blank" {
            tab.isStartPage = true
            startPage.isHidden = false
        }
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === currentTab?.webView else { return }
        activity.stopAnimating()
        updateNavButtons()
    }

    /// 地址栏本身就是 .swf 直链时，不让 WKWebView 渲染，直接走下载播放流程。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, Self.isDirectSWF(url) {
            decisionHandler(.cancel)
            confirmDownload(url)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           let mime = response.mimeType?.lowercased(),
           mime.contains("shockwave-flash") && response.statusCode == 200 {
            decisionHandler(.cancel)
            confirmDownload(response.url ?? webView.url)
            return
        }
        decisionHandler(.allow)
    }

    private static func isDirectSWF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "swf"
    }

    // MARK: - SWF 嗅探

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "swfSniff",
              let body = message.body as? [String: Any],
              let urls = body["urls"] as? [String],
              let web = message.webView,
              let tabIndex = tabs.firstIndex(where: { $0.webView === web }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let tab = self.tabs[tabIndex]
            var merged = tab.detectedSWFs
            for url in urls where !merged.contains(url) { merged.append(url) }
            tab.detectedSWFs = Array(merged.prefix(24))
            if tabIndex == self.currentIndex { self.updateSWFBadge() }
        }
    }

    @objc private func showDetectedSWFs() {
        guard let tab = currentTab, !tab.detectedSWFs.isEmpty else {
            showError(L("browser.swfNone"))
            return
        }
        let sheet = UIAlertController(title: L("browser.swfListTitle"),
                                      message: L("browser.swfListMessage", String(tab.detectedSWFs.count)),
                                      preferredStyle: .actionSheet)
        for (index, value) in tab.detectedSWFs.enumerated() {
            let label = "\(index + 1). \((value as NSString).lastPathComponent)"
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                guard let self = self, let url = URL(string: value) else { return }
                self.confirmDownload(url)
            })
        }
        sheet.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = swfButton
            popover.sourceRect = swfButton.bounds
        }
        present(sheet, animated: true)
    }

    private func confirmDownload(_ url: URL?) {
        guard let url = url else { return }
        let alert = UIAlertController(title: L("browser.directSWFTitle"),
                                      message: L("browser.directSWFMessage", url.absoluteString),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("browser.downloadAction"), style: .default) { [weak self] _ in
            self?.downloadAndPlay(Self.downloadCandidates(for: url))
        })
        present(alert, animated: true)
    }

    /// 构造候选下载地址：原始 URL 优先；对已知多 CDN 站点补镜像；再补 www 变体。
    private static func downloadCandidates(for url: URL) -> [URL] {
        var result: [URL] = [url]
        guard let host = url.host?.lowercased() else { return result }
        let path = url.path
        let query = url.query.map { "?\($0)" } ?? ""
        func make(_ h: String) -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = h
            comps.path = path
            comps.query = url.query
            return comps.url
        }
        // oldswf 系列：主站 + 多线程镜像域名（源站 getUrls 使用）。
        if host == "oldswf.com" || host.hasSuffix(".oldswf.com") {
            for mirror in ["vvhan.oldswf.com", "fast.oldswf.com", "fastali.oldswf.com", "www.oldswf.com"] {
                if let u = make(mirror), !result.contains(u) { result.append(u) }
            }
        } else {
            if !host.hasPrefix("www."), let u = make("www.\(host)"), !result.contains(u) { result.append(u) }
        }
        _ = query
        return result
    }

    // MARK: - 下载并用本地播放器打开（多候选回退）

    private func buildBusyOverlay() {
        busyOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        busyOverlay.isHidden = true
        view.addSubview(busyOverlay)

        busyCard.backgroundColor = UIColor(hex: 0x1C1C1E)
        busyCard.layer.cornerRadius = 16
        busyOverlay.addSubview(busyCard)

        busySpinner.color = .white
        busyCard.addSubview(busySpinner)

        busyLabel.textColor = .white
        busyLabel.font = UIFont.systemFont(ofSize: 12.5)
        busyLabel.textAlignment = .center
        busyLabel.numberOfLines = 2
        busyCard.addSubview(busyLabel)
    }

    private func setBusy(_ busy: Bool) {
        busyOverlay.isHidden = !busy
        if busy {
            busySpinner.startAnimating()
            view.bringSubviewToFront(busyOverlay)
        } else {
            busySpinner.stopAnimating()
        }
    }

    private func downloadAndPlay(_ candidates: [URL]) {
        setBusy(true)
        let refererBase = currentTab?.url ?? candidates.first
        tryDownload(candidates, index: 0, refererBase: refererBase)
    }

    private func tryDownload(_ candidates: [URL], index: Int, refererBase: URL?) {
        guard index < candidates.count else {
            setBusy(false)
            showError(L("browser.invalidSWF"))
            return
        }
        let url = candidates[index]
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
                         + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let referer = refererBase.flatMap { "\($0.scheme ?? "https")://\($0.host ?? "")/" }
            ?? "\(url.scheme ?? "https")://\(url.host ?? "")/"
        request.setValue(referer, forHTTPHeaderField: "Referer")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    self.tryDownload(candidates, index: index + 1, refererBase: refererBase)
                    return
                }
                guard error == nil, let data = data, !data.isEmpty,
                      data.count <= 60 * 1024 * 1024 else {
                    self.tryDownload(candidates, index: index + 1, refererBase: refererBase)
                    return
                }
                let signature = String(decoding: data.prefix(3), as: UTF8.self)
                guard ["FWS", "CWS", "ZWS"].contains(signature) else {
                    self.tryDownload(candidates, index: index + 1, refererBase: refererBase)
                    return
                }
                self.setBusy(false)
                let rawName = url.lastPathComponent.removingPercentEncoding ?? ""
                let name = rawName.isEmpty ? "flash.swf" : rawName
                do {
                    let item = try LibraryStore.shared.importRemote(data: data, fileName: name)
                    LibraryStore.shared.touch(item.id)
                    self.navigationController?.pushViewController(PlayerViewController(item: item), animated: true)
                } catch {
                    self.showError(L("browser.invalidSWF"))
                }
            }
        }.resume()
    }

    // MARK: - 提示

    private func showError(_ message: String) {
        let alert = UIAlertController(title: L("browser.loadFailedTitle"),
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func showToast(_ message: String) {
        toastLabel?.removeFromSuperview()
        let label = UILabel()
        label.text = message
        label.font = UIFont.systemFont(ofSize: 12.5)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        let width = min(view.bounds.width - 48, 340)
        label.frame = CGRect(x: (view.bounds.width - width) / 2,
                             y: view.safeAreaInsets.top + 62, width: width, height: 46)
        view.addSubview(label)
        toastLabel = label
        UIView.animate(withDuration: 0.3, delay: 3.2, options: .curveEaseInOut, animations: {
            label.alpha = 0
        }, completion: { _ in label.removeFromSuperview() })
    }

    // MARK: - UICollectionView 数据源

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === historyGrid { return history.count }
        if collectionView === tabsCollection { return tabs.count }
        return 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === historyGrid {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "HistoryCell", for: indexPath) as! HistoryCell
            let entry = history[indexPath.item]
            cell.nameLabel.text = entry.title
            cell.tag = indexPath.item
            loadFavicon(into: cell, entry: entry, index: indexPath.item)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TabCell", for: indexPath) as! TabCell
        let tab = tabs[indexPath.item]
        cell.hostLabel.text = tab.url?.host ?? L("browser.startTitle")
        cell.titleLabel.text = tab.title.isEmpty ? (tab.url?.host ?? L("browser.tabBlank")) : tab.title
        cell.layer.borderWidth = indexPath.item == currentIndex ? 2 : 1
        cell.layer.borderColor = (indexPath.item == currentIndex ? Theme.red : Theme.hairline).cgColor
        cell.index = indexPath.item
        cell.closeBtn.tag = indexPath.item
        cell.closeBtn.removeTarget(nil, action: nil, for: .touchUpInside)
        cell.closeBtn.addTarget(self, action: #selector(closeTabButton(_:)), for: .touchUpInside)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === historyGrid {
            guard let url = normalizedURL(history[indexPath.item].url) else { return }
            addressField.resignFirstResponder()
            loadCurrentTab(url)
        } else if collectionView === tabsCollection {
            selectTab(at: indexPath.item)
        }
    }

    @objc private func closeTabButton(_ sender: UIButton) {
        closeTab(at: sender.tag)
    }

    private func loadFavicon(into cell: HistoryCell, entry: HistoryEntry, index: Int) {
        cell.iconView.image = UIImage(systemName: "globe.americas.fill")
        guard let fav = entry.favicon, let url = URL(string: fav) else { return }
        URLSession.shared.dataTask(with: url) { [weak self, weak cell] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self = self, let cell = cell,
                      self.historyGrid.cellForItem(at: IndexPath(item: index, section: 0)) === cell else { return }
                cell.iconView.image = image
            }
        }.resume()
    }

    // MARK: - UIGestureRecognizerDelegate（标签面板点外部关闭，但不吞列表点击）

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view, view.isDescendant(of: tabsCollection) { return false }
        return true
    }
}

// MARK: - 弱引用 message handler，避免 WKWebView 循环引用

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - 脚本常量

extension WebBrowserViewController {

    /// 读取标题和 favicon（含 apple-touch-icon），用于历史宫格。
    static let pageMetaScript = #"""
    (function () {
      var title = document.title || "";
      var icon = null;
      var links = document.querySelectorAll('link[rel]');
      var preferred = ['apple-touch-icon-precomposed','apple-touch-icon','icon','shortcut icon'];
      for (var p = 0; p < preferred.length && !icon; p++) {
        for (var i = 0; i < links.length; i++) {
          var rel = (links[i].getAttribute('rel') || '').toLowerCase();
          if (rel.indexOf(preferred[p]) >= 0) {
            var href = links[i].getAttribute('href');
            if (href) { try { icon = new URL(href, document.baseURI).href; } catch (e) {} }
            if (icon) { break; }
          }
        }
      }
      if (!icon) { try { icon = new URL('/favicon.ico', document.location.origin).href; } catch (e) {} }
      return { title: title, icon: icon };
    })();
    """#

    /// 嗅探页面中的 SWF 资源：
    ///  - HTML 属性（embed/object/param/a/iframe/input）
    ///  - 通用 HTML 属性里出现的 .swf
    ///  - JS 字符串字面量中的 .swf（如 oldswf 的 loadSwf("/data/game_2024/74536.swf")）
    ///  - 以 document.baseURI 解析成绝对 URL，去重后用 MutationObserver 跟踪动态内容。
    static let sniffScript = #"""
    (function () {
      function abs(u) {
        try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
      }
      function collect() {
        var found = [];
        function add(u) {
          if (!u) { return; }
          var s = String(u);
          // 跳过纯数据/脚本资源误报
          if (/^data:/i.test(s)) { return; }
          var full = abs(s);
          if (!full || !/^https?:\/\//i.test(full)) { return; }
          if (!/\.swf(\?|#|$)/i.test(full)) { return; }
          found.push(full.split('#')[0]);
        }

        // 1) 常见元素属性
        var nodes = document.querySelectorAll(
          'embed[src],object[data],object[codebase],param[name],a[href],area[href],iframe[src],input[value]'
        );
        for (var i = 0; i < nodes.length; i++) {
          var n = nodes[i];
          var tag = n.tagName.toLowerCase();
          if (tag === 'embed' || tag === 'iframe') { add(n.getAttribute('src')); }
          else if (tag === 'object') { add(n.getAttribute('data')); add(n.getAttribute('codebase')); }
          else if (tag === 'param') {
            var name = (n.getAttribute('name') || '').toLowerCase();
            if (name === 'movie' || name === 'src' || name === 'data' || name === 'flashvars') { add(n.getAttribute('value')); }
          } else if (tag === 'a' || tag === 'area') { add(n.getAttribute('href')); }
          else if (tag === 'input') { add(n.getAttribute('value')); }
        }

        // 2) 整个文档 HTML 里带属性形式的 .swf
        try {
          var html = document.documentElement.outerHTML;
          var re = /(?:src|data|value|href|movie|url)\s*=\s*["'][^"']*?\.swf(?:\?[^"']*)?["']/gi;
          var m;
          while ((m = re.exec(html)) !== null) {
            var q = m[0].indexOf('=');
            var v = m[0].substring(q + 1).trim().replace(/^["']|["']$/g, '');
            add(v);
          }
        } catch (e) {}

        // 3) JS 字符串字面量里的 .swf（关键：oldswf 的 loadSwf("/xxx.swf")）
        try {
          var scripts = document.querySelectorAll('script');
          var stre = /(["'`])([^"'`]*?\.swf(?:\?[^"'`]*)?)\1/gi;
          for (var s = 0; s < scripts.length; s++) {
            var text = scripts[s].textContent || '';
            var sm;
            while ((sm = stre.exec(text)) !== null) { add(sm[2]); }
          }
        } catch (e) {}

        // 4) 纯文本里裸露的 .swf 路径
        try {
          var bodyText = document.body ? document.body.innerHTML : '';
          var bare = /([^\s"'<>()]*\.swf(?:\?[^\s"'<>]*)?)/gi;
          var bm;
          while ((bm = bare.exec(bodyText)) !== null) { add(bm[1]); }
        } catch (e) {}

        var seen = {}, out = [];
        for (var j = 0; j < found.length; j++) {
          var clean = found[j].split('#')[0];
          if (!seen[clean]) { seen[clean] = 1; out.push(clean); }
        }
        return out.slice(0, 24);
      }
      function report() {
        try {
          window.webkit.messageHandlers.swfSniff.postMessage({ urls: collect() });
        } catch (e) {}
      }
      window.__swfSniff = report;
      if (document.readyState === 'complete' || document.readyState === 'interactive') {
        setTimeout(report, 300);
      } else {
        document.addEventListener('DOMContentLoaded', function () { setTimeout(report, 300); });
      }
      window.addEventListener('load', function () { setTimeout(report, 500); });
      if (window.MutationObserver) {
        var timer = null;
        var observer = new MutationObserver(function () {
          if (timer) { return; }
          timer = setTimeout(function () { timer = null; report(); }, 700);
        });
        observer.observe(document.documentElement || document,
                         { childList: true, subtree: true, attributes: true });
      }
    })();
    """#
}
