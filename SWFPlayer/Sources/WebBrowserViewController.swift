import UIKit
import WebKit

/// 内置网页浏览器：直接访问网址，嗅探页面中的 Flash(SWF) 资源，下载到本地播放。
///
/// 设计取舍：
///  - 第三方网页内部直接注入 Ruffle 不可靠（跨域/CSP/WASM publicPath），
///    因此采用「网页照常展示 → 嗅探 .swf → 校验 → 下载 → 本地 PlayerViewController 播放」。
///  - 支持多窗口（标签页）：每个窗口一个独立 WKWebView，全屏卡片式管理。
///  - 历史按主域名（eTLD+1）去重，宫格展示 favicon + 站点名。
final class WebBrowserViewController: UIViewController,
                                     WKNavigationDelegate,
                                     WKUIDelegate,
                                     WKScriptMessageHandler,
                                     UITextFieldDelegate,
                                     UICollectionViewDataSource,
                                     UICollectionViewDelegate,
                                     UICollectionViewDelegateFlowLayout {

    // MARK: - 标签页模型

    private final class Tab {
        let id = UUID()
        let webView: WKWebView
        var title: String = ""
        var url: URL?
        var isStartPage: Bool = true
        /// 页面里抓到的全部候选（按置信度降序）。
        var rawSWFs: [String] = []
        var swfScores: [String: Int] = [:]
        /// 经过 Range 探测、确认真的是 SWF 的候选。
        var verifiedSWFs: [String] = []
        var swfSizes: [String: Int] = [:]
        var isVerifying: Bool = false
        var progress: Double = 0
        var thumbnail: UIImage?
        var progressObservation: NSKeyValueObservation?

        init(configuration: WKWebViewConfiguration) {
            self.webView = WKWebView(frame: .zero, configuration: configuration)
        }

        var host: String { url?.host ?? "" }

        var displayTitle: String {
            if isStartPage { return L("browser.tabBlank") }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? host : trimmed
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
    /// Flash 角标：独立按钮，图标统一用黑色 bolt，单行显示，不挤占输入框。
    private let swfButton = UIButton(type: .system)
    /// 地址栏内底部进度条（Safari 式），取代原先挤在输入框右侧的转圈。
    private let progressBar = UIView()
    private var isLayingOut = false

    // MARK: - 窗口管理（全屏卡片）

    private let tabsPanel = UIView()
    private let tabsSearchField = UITextField()
    private let tabsCountLabel = UILabel()
    private let tabsDoneButton = UIButton(type: .system)
    private let tabsAddButton = UIButton(type: .system)
    private let tabsFooter = UIView()
    private let tabsCollection: UICollectionView
    private var tabsPanelVisible = false
    private var filteredIndices: [Int] = []
    private var staggerCells = false
    private var pendingShowSWFList = false

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
    private let historyEmptyLabel = UILabel()

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
    private static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
    private var history: [HistoryEntry] = []
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
        // 站内 window.open / target=_blank 需要这个开关，否则点击后毫无反应。
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webConfiguration = config

        let gridLayout = UICollectionViewFlowLayout()
        gridLayout.minimumLineSpacing = 14
        gridLayout.minimumInteritemSpacing = 12
        self.historyGrid = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)

        let tabsLayout = UICollectionViewFlowLayout()
        tabsLayout.scrollDirection = .vertical
        tabsLayout.minimumLineSpacing = 16
        tabsLayout.minimumInteritemSpacing = 14
        tabsLayout.sectionInset = UIEdgeInsets(top: 4, left: 16, bottom: 24, right: 16)
        self.tabsCollection = UICollectionView(frame: .zero, collectionViewLayout: tabsLayout)

        super.init(nibName: nil, bundle: nil)
        if let url = url {
            addTabAndSelect(load: url)
        } else {
            addTabAndSelect(load: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        webConfiguration.userContentController.removeScriptMessageHandler(forName: "swfSniff")
    }

    override var prefersStatusBarHidden: Bool { false }

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
        rebuildFilteredTabs()
        attachCurrentWebView()
        updateUIForCurrentTab()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 进入浏览器时不自动聚焦地址栏（不弹键盘），用户点了才输入。
        guard !didInitialAppearance else { return }
        didInitialAppearance = true
        addressField.resignFirstResponder()
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
        tabsButton.addTarget(self, action: #selector(showTabsPanel), for: .touchUpInside)

        addressField.borderStyle = .roundedRect
        addressField.returnKeyType = .go
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.clearButtonMode = .whileEditing
        addressField.font = UIFont.systemFont(ofSize: 14)
        addressField.textColor = Theme.ink
        addressField.backgroundColor = Theme.groupedBackground
        addressField.layer.borderWidth = 1
        addressField.layer.borderColor = Theme.hairline.cgColor
        addressField.delegate = self
        // 进度条贴在输入框内底部，必须裁到圆角以内，否则会压到边框和页面。
        addressField.clipsToBounds = true
        view.addSubview(addressField)

        progressBar.backgroundColor = Theme.red
        progressBar.layer.cornerRadius = 1.5
        progressBar.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        progressBar.alpha = 0
        addressField.addSubview(progressBar)

        swfButton.addTarget(self, action: #selector(showDetectedSWFs), for: .touchUpInside)
        view.addSubview(swfButton)
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
        historyEmptyLabel.text = L("browser.historyEmpty")
        historyClearButton.setTitle(L("browser.historyClear"), for: .normal)
        tabsSearchField.placeholder = L("browser.tabsSearch")
        tabsDoneButton.setTitle(L("browser.tabsDone"), for: .normal)
        updateSWFBadge()
        updateTabsBadge()
        updateTabsCount()
    }

    private func setButton(_ button: UIButton, symbol: String, pointSize: CGFloat = 15) {
        let image = UIImage(systemName: symbol,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
        button.setImage(image, for: .normal)
    }

    // MARK: - 布局

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        isLayingOut = true
        defer { isLayingOut = false }
        let width = view.bounds.width
        let insets = view.safeAreaInsets
        let top = insets.top + 8
        let barHeight: CGFloat = 38
        let pad: CGFloat = 8
        let side: CGFloat = 30
        // 图标之间不再留缝，把省下来的宽度全部让给地址栏。
        let gap: CGFloat = 0

        setButton(closeButton, symbol: "xmark", pointSize: 13)
        setButton(backButton, symbol: "chevron.left", pointSize: 15)
        setButton(forwardButton, symbol: "chevron.right", pointSize: 15)
        setButton(reloadButton, symbol: "arrow.clockwise", pointSize: 14)
        // 窗口按钮的图标由 updateTabsBadge 统一用 configuration 管理（不带数字）。

        closeButton.frame = CGRect(x: pad, y: top, width: side, height: barHeight)
        backButton.frame = CGRect(x: closeButton.frame.maxX + gap, y: top, width: side, height: barHeight)
        forwardButton.frame = CGRect(x: backButton.frame.maxX + gap, y: top, width: side, height: barHeight)

        // 右侧：刷新 / Flash 角标 / 窗口，一行排开互不重叠。
        // 角标宽度按内容实测，避免数字被裁掉。
        updateSWFBadge()
        let badgeW = max(28, ceil(swfButton.sizeThatFits(CGSize(width: 260, height: barHeight)).width))
        reloadButton.frame = CGRect(x: width - pad - side, y: top, width: side, height: barHeight)
        swfButton.frame = CGRect(x: reloadButton.frame.minX - badgeW - gap,
                                 y: top, width: badgeW, height: barHeight)
        tabsButton.frame = CGRect(x: swfButton.frame.minX - side - gap,
                                  y: top, width: side, height: barHeight)
        updateTabsBadge()

        // 地址栏吃掉中间所有剩余宽度。
        let fieldX = forwardButton.frame.maxX + 6
        let fieldW = max(80, tabsButton.frame.minX - 6 - fieldX)
        addressField.frame = CGRect(x: fieldX, y: top, width: fieldW, height: barHeight)
        addressField.layer.cornerRadius = 10

        let webTop = top + barHeight + 8
        for tab in tabs {
            tab.webView.frame = CGRect(x: 0, y: webTop, width: width, height: view.bounds.height - webTop)
        }

        // 进度条画在地址栏内部底沿（不占整页、不压边框）。
        let progress = currentTab?.progress ?? 0
        var barW = progressBar.frame.width
        if progress > 0 && progress < 1 { barW = max(6, progressTrackWidth * CGFloat(progress)) }
        if progressBar.alpha < 0.01 { barW = 0 }
        progressBar.frame = progressFrame(width: barW)
        addressField.bringSubviewToFront(progressBar)

        busyOverlay.frame = view.bounds
        let cardSize = CGSize(width: 168, height: 116)
        busyCard.frame = CGRect(x: (width - cardSize.width) / 2,
                                y: (view.bounds.height - cardSize.height) / 2,
                                width: cardSize.width, height: cardSize.height)
        busySpinner.frame = CGRect(x: (cardSize.width - 34) / 2, y: 20, width: 34, height: 34)
        busyLabel.frame = CGRect(x: 10, y: 64, width: cardSize.width - 20, height: 34)

        layoutStartPage(webTop: webTop)
        layoutTabsPanel()
    }

    // MARK: - 标签页管理

    @discardableResult
    private func addTabAndSelect(load url: URL?) -> Tab {
        let tab = Tab(configuration: webConfiguration)
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        tab.webView.allowsBackForwardNavigationGestures = true
        tab.webView.scrollView.contentInsetAdjustmentBehavior = .never
        tab.webView.backgroundColor = Theme.background
        tab.webView.allowsLinkPreview = true
        // 进度：KVO 驱动底部进度条。
        tab.progressObservation = tab.webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak tab] web, _ in
            guard let self = self, let tab = tab else { return }
            DispatchQueue.main.async {
                guard tab === self.currentTab else { return }
                self.animateProgress(web.estimatedProgress, tab: tab)
            }
        }
        tabs.append(tab)
        currentIndex = tabs.count - 1
        if let url = url {
            tab.url = url
            tab.isStartPage = false
            tab.webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        } else {
            tab.webView.load(URLRequest(url: URL(string: "about:blank")!))
        }
        if isViewLoaded {
            attachCurrentWebView()
            rebuildFilteredTabs()
            updateUIForCurrentTab()
        }
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

    /// 只改模型 + 重新挂载当前页，不碰 collection（交给调用方控制动画）。
    @discardableResult
    private func removeTabModel(at index: Int) -> Bool {
        guard tabs.indices.contains(index), tabs.count > 1 else { return false }
        let tab = tabs[index]
        // message handler 挂在共享 configuration 上，不能按 tab 移除，否则影响其它窗口。
        tab.webView.removeFromSuperview()
        tab.progressObservation = nil
        tabs.remove(at: index)
        if currentIndex >= tabs.count { currentIndex = tabs.count - 1 }
        else if index < currentIndex { currentIndex -= 1 }
        return true
    }

    private func closeTab(at index: Int) {
        guard removeTabModel(at: index) else { return }
        rebuildFilteredTabs()
        attachCurrentWebView()
        updateUIForCurrentTab()
        tabsCollection.reloadData()
        updateTabsCount()
    }

    private func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let changed = index != currentIndex
        currentIndex = index
        attachCurrentWebView()
        updateUIForCurrentTab()
        if changed {
            // 卡片切换的收尾：内容轻微回弹，和面板淡出同步。
            let web = tabs[index].webView
            web.alpha = 1
            web.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
            UIView.animate(withDuration: 0.28, delay: 0.04, options: .curveEaseOut) {
                web.transform = .identity
            }
        }
        hideTabsPanel()
    }

    private func updateUIForCurrentTab() {
        guard let tab = currentTab else { return }
        addressField.text = tab.isStartPage ? nil : tab.url?.absoluteString
        startPage.isHidden = !tab.isStartPage
        updateNavButtons()
        updateSWFBadge()
        updateTabsBadge()
        applyProgress(tab)
        historyGrid.reloadData()
        historyEmptyLabel.isHidden = !history.isEmpty
        if tabsPanelVisible {
            rebuildFilteredTabs()
            tabsCollection.reloadData()
            updateTabsCount()
        }
    }

    private func updateTabsBadge() {
        // 不再在图标后面叠数字（30pt 宽度里数字会被裁掉），数量只在窗口面板底部展示。
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "square.on.square",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        config.baseForegroundColor = Theme.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        tabsButton.configuration = config
        tabsButton.accessibilityLabel = L("browser.tabs") + " (" + String(tabs.count) + ")"
    }

    // MARK: - 地址栏内底部进度条

    private enum ProgressMetrics {
        static let height: CGFloat = 3
        static let inset: CGFloat = 1
    }

    /// 输入框内部可画宽度（扣掉左右 1pt，避免压到边框）。
    private var progressTrackWidth: CGFloat {
        max(0, addressField.bounds.width - ProgressMetrics.inset * 2)
    }

    private func progressFrame(width: CGFloat) -> CGRect {
        // 再往上让 1pt，正好压在边框内侧，不和边框线重叠。
        CGRect(x: ProgressMetrics.inset,
               y: max(0, addressField.bounds.height - ProgressMetrics.height - 1),
               width: min(width, progressTrackWidth),
               height: ProgressMetrics.height)
    }

    private func applyProgress(_ tab: Tab) {
        if tab.progress > 0 && tab.progress < 1 {
            progressBar.alpha = 1
            progressBar.frame = progressFrame(width: max(6, progressTrackWidth * CGFloat(tab.progress)))
        } else {
            progressBar.alpha = 0
            progressBar.frame = progressFrame(width: 0)
        }
    }

    private func animateProgress(_ value: Double, tab: Tab) {
        tab.progress = value
        addressField.bringSubviewToFront(progressBar)
        if value >= 1.0 {
            UIView.animate(withDuration: 0.18, delay: 0, options: .beginFromCurrentState, animations: {
                self.progressBar.alpha = 1
                self.progressBar.frame = self.progressFrame(width: self.progressTrackWidth)
            }, completion: { _ in
                UIView.animate(withDuration: 0.28, delay: 0.14, options: .curveEaseOut, animations: {
                    self.progressBar.alpha = 0
                }, completion: { _ in
                    self.progressBar.frame = self.progressFrame(width: 0)
                })
            })
        } else if value > 0.01 {
            progressBar.alpha = 1
            UIView.animate(withDuration: 0.2, delay: 0, options: .beginFromCurrentState, animations: {
                self.progressBar.frame = self.progressFrame(width: max(6, self.progressTrackWidth * CGFloat(value)))
            })
        }
    }

    /// 加载失败/中断时把进度条收干净。
    private func finishProgress() {
        UIView.animate(withDuration: 0.2, animations: {
            self.progressBar.alpha = 0
        }, completion: { _ in
            self.progressBar.frame = self.progressFrame(width: 0)
            self.currentTab?.progress = 0
        })
    }

    // MARK: - 全屏窗口管理（卡片式）

    private func buildTabsPanel() {
        tabsPanel.isHidden = true
        tabsPanel.backgroundColor = Theme.background
        tabsPanel.layer.cornerRadius = 20
        tabsPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tabsPanel.clipsToBounds = true
        view.addSubview(tabsPanel)

        // 顶部搜索框
        tabsSearchField.backgroundColor = Theme.groupedBackground
        tabsSearchField.borderStyle = .none
        tabsSearchField.font = UIFont.systemFont(ofSize: 15)
        tabsSearchField.textColor = Theme.ink
        tabsSearchField.placeholder = L("browser.tabsSearch")
        tabsSearchField.clearButtonMode = .whileEditing
        tabsSearchField.returnKeyType = .search
        tabsSearchField.delegate = self
        tabsSearchField.autocorrectionType = .no
        tabsSearchField.autocapitalizationType = .none
        tabsSearchField.layer.cornerRadius = 11
        tabsSearchField.addTarget(self, action: #selector(tabsSearchChanged), for: .editingChanged)
        let glass = UIImageView(image: UIImage(systemName: "magnifyingglass",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
        glass.tintColor = Theme.secondary
        glass.contentMode = .center
        let glassWrap = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 36))
        glass.frame = glassWrap.bounds
        glassWrap.addSubview(glass)
        tabsSearchField.leftView = glassWrap
        tabsSearchField.leftViewMode = .always
        tabsPanel.addSubview(tabsSearchField)

        tabsCollection.backgroundColor = .clear
        tabsCollection.dataSource = self
        tabsCollection.delegate = self
        tabsCollection.alwaysBounceVertical = true
        tabsCollection.contentInsetAdjustmentBehavior = .never
        tabsCollection.register(TabCardCell.self, forCellWithReuseIdentifier: "TabCardCell")
        tabsPanel.addSubview(tabsCollection)

        tabsFooter.backgroundColor = Theme.background
        tabsPanel.addSubview(tabsFooter)

        let footerLine = UIView()
        footerLine.backgroundColor = Theme.hairline
        footerLine.tag = 902
        tabsFooter.addSubview(footerLine)

        tabsCountLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        tabsCountLabel.textColor = Theme.ink
        tabsFooter.addSubview(tabsCountLabel)

        tabsAddButton.layer.cornerRadius = 19
        tabsAddButton.backgroundColor = Theme.groupedBackground
        tabsAddButton.tintColor = Theme.ink
        tabsAddButton.setImage(UIImage(systemName: "plus",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)),
                               for: .normal)
        tabsAddButton.addTarget(self, action: #selector(newTabFromPanel), for: .touchUpInside)
        tabsFooter.addSubview(tabsAddButton)

        tabsDoneButton.setTitleColor(Theme.ink, for: .normal)
        tabsDoneButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        tabsDoneButton.addTarget(self, action: #selector(hideTabsPanelAction), for: .touchUpInside)
        tabsFooter.addSubview(tabsDoneButton)
    }

    private func layoutTabsPanel() {
        let width = view.bounds.width
        let height = view.bounds.height
        let safeTop = view.safeAreaInsets.top
        let safeBottom = view.safeAreaInsets.bottom
        tabsPanel.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let searchH: CGFloat = 36
        tabsSearchField.frame = CGRect(x: 16, y: safeTop + 10, width: width - 32, height: searchH)
        tabsSearchField.layer.cornerRadius = searchH / 2

        let footerH = 58 + safeBottom
        tabsFooter.frame = CGRect(x: 0, y: height - footerH, width: width, height: footerH)
        tabsFooter.viewWithTag(902)?.frame = CGRect(x: 0, y: 0, width: width, height: 0.5)

        let rowY: CGFloat = 9
        tabsCountLabel.frame = CGRect(x: 20, y: rowY, width: 160, height: 40)
        tabsDoneButton.frame = CGRect(x: width - 20 - 52, y: rowY, width: 52, height: 40)
        tabsAddButton.frame = CGRect(x: (width - 38) / 2, y: rowY + 1, width: 38, height: 38)

        let gridTop = tabsSearchField.frame.maxY + 14
        tabsCollection.frame = CGRect(x: 0, y: gridTop, width: width, height: max(0, tabsFooter.frame.minY - gridTop))
    }

    private func layoutStartPage(webTop: CGFloat) {
        startPage.frame = CGRect(x: 0, y: webTop, width: view.bounds.width, height: view.bounds.height - webTop)
        layoutStartPageContent(webTop: webTop)
    }

    @objc private func tabsSearchChanged() {
        rebuildFilteredTabs()
        tabsCollection.reloadData()
    }

    private func rebuildFilteredTabs() {
        let keyword = (tabsSearchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if keyword.isEmpty {
            filteredIndices = Array(tabs.indices)
        } else {
            filteredIndices = tabs.indices.filter { index in
                let tab = tabs[index]
                return tab.displayTitle.lowercased().contains(keyword)
                    || tab.host.lowercased().contains(keyword)
                    || (tab.url?.absoluteString.lowercased().contains(keyword) ?? false)
            }
        }
    }

    private func updateTabsCount() {
        tabsCountLabel.text = L("browser.tabsCount", String(tabs.count))
    }

    @objc private func showTabsPanel() {
        guard !tabsPanelVisible else { return }
        addressField.resignFirstResponder()
        tabsSearchField.text = nil
        rebuildFilteredTabs()
        staggerCells = true
        tabsCollection.reloadData()
        updateTabsCount()

        tabsPanelVisible = true
        tabsPanel.isHidden = false
        tabsPanel.alpha = 0
        tabsPanel.transform = CGAffineTransform(translationX: 0, y: 26).scaledBy(x: 0.985, y: 0.985)
        view.bringSubviewToFront(tabsPanel)
        UIView.animate(withDuration: 0.34, delay: 0, usingSpringWithDamping: 0.92,
                       initialSpringVelocity: 0.4, options: [.curveEaseOut], animations: {
            self.tabsPanel.alpha = 1
            self.tabsPanel.transform = .identity
        }, completion: { _ in
            self.staggerCells = false
        })
    }

    @objc private func hideTabsPanelAction() {
        hideTabsPanel()
    }

    private func hideTabsPanel() {
        guard tabsPanelVisible else { return }
        tabsPanelVisible = false
        tabsSearchField.resignFirstResponder()
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.tabsPanel.alpha = 0
            self.tabsPanel.transform = CGAffineTransform(translationX: 0, y: 16)
        }, completion: { _ in
            self.tabsPanel.isHidden = true
            self.tabsPanel.alpha = 1
            self.tabsPanel.transform = .identity
        })
    }

    @objc private func newTabFromPanel() {
        addTabAndSelect(load: nil)
        rebuildFilteredTabs()
        tabsCollection.reloadData()
        updateTabsCount()
        if let last = filteredIndices.firstIndex(of: currentIndex) {
            tabsCollection.scrollToItem(at: IndexPath(item: last, section: 0), at: .bottom, animated: true)
        }
        hideTabsPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.addressField.becomeFirstResponder()
        }
    }

    /// 卡片 cell：页面截图 + 底部标题条，参考 Safari/Chrome 的窗口管理。
    private final class TabCardCell: UICollectionViewCell {
        private let snapshot = UIImageView()
        private let placeholder = UIView()
        private let placeholderIcon = UIImageView()
        private let placeholderLabel = UILabel()
        private let footer = UIView()
        private let separator = UIView()
        private let favicon = UIImageView()
        private let titleLabel = UILabel()
        private let closeButton = UIButton(type: .system)
        var onClose: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerRadius = 14
            contentView.layer.borderWidth = 1
            contentView.layer.borderColor = Theme.hairline.cgColor
            contentView.backgroundColor = Theme.card
            contentView.clipsToBounds = true

            snapshot.contentMode = .scaleAspectFill
            snapshot.clipsToBounds = true
            snapshot.backgroundColor = Theme.groupedBackground
            contentView.addSubview(snapshot)

            placeholder.backgroundColor = Theme.groupedBackground
            contentView.addSubview(placeholder)

            placeholderIcon.image = UIImage(systemName: "globe.americas.fill",
                                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .regular))
            placeholderIcon.tintColor = UIColor(hex: 0xC9C9D2)
            placeholderIcon.contentMode = .center
            placeholder.addSubview(placeholderIcon)

            placeholderLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            placeholderLabel.textColor = Theme.secondary
            placeholderLabel.textAlignment = .center
            placeholderLabel.lineBreakMode = .byTruncatingTail
            placeholder.addSubview(placeholderLabel)

            footer.backgroundColor = Theme.card
            contentView.addSubview(footer)

            separator.backgroundColor = Theme.hairline
            footer.addSubview(separator)

            favicon.image = UIImage(systemName: "globe",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular))
            favicon.tintColor = Theme.ink
            favicon.contentMode = .scaleAspectFit
            footer.addSubview(favicon)

            titleLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .medium)
            titleLabel.textColor = Theme.ink
            titleLabel.lineBreakMode = .byTruncatingTail
            footer.addSubview(titleLabel)

            closeButton.setImage(UIImage(systemName: "xmark",
                                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)),
                                 for: .normal)
            closeButton.tintColor = Theme.ink
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            footer.addSubview(closeButton)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func closeTapped() {
            onClose?()
        }

        func configure(title: String, host: String, thumbnail: UIImage?, isCurrent: Bool) {
            snapshot.image = thumbnail
            placeholder.isHidden = thumbnail != nil
            placeholderLabel.text = host.isEmpty ? title : host
            titleLabel.text = title
            contentView.layer.borderWidth = isCurrent ? 2.5 : 1
            contentView.layer.borderColor = (isCurrent ? Theme.ink : Theme.hairline).cgColor
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let w = contentView.bounds.width
            let h = contentView.bounds.height
            let footerH: CGFloat = 33
            snapshot.frame = CGRect(x: 0, y: 0, width: w, height: h - footerH)
            placeholder.frame = snapshot.frame
            placeholderIcon.frame = CGRect(x: (w - 40) / 2, y: (h - footerH) / 2 - 32, width: 40, height: 40)
            placeholderLabel.frame = CGRect(x: 10, y: placeholderIcon.frame.maxY + 8, width: w - 20, height: 18)
            footer.frame = CGRect(x: 0, y: h - footerH, width: w, height: footerH)
            separator.frame = CGRect(x: 0, y: 0, width: w, height: 0.5)
            favicon.frame = CGRect(x: 9, y: (footerH - 15) / 2, width: 15, height: 15)
            closeButton.frame = CGRect(x: w - 34, y: (footerH - 30) / 2, width: 30, height: 30)
            titleLabel.frame = CGRect(x: 30, y: 0, width: max(0, closeButton.frame.minX - 34), height: footerH)
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            transform = .identity
            alpha = 1
            snapshot.image = nil
            titleLabel.text = nil
            placeholderLabel.text = nil
            onClose = nil
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

        tipCard.backgroundColor = Theme.groupedBackground
        tipCard.layer.cornerRadius = 16
        startPage.addSubview(tipCard)

        tipIcon.image = UIImage(systemName: "bolt.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        tipIcon.tintColor = Theme.ink
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

        historyClearButton.setTitleColor(Theme.secondary, for: .normal)
        historyClearButton.titleLabel?.font = UIFont.systemFont(ofSize: 12.5, weight: .medium)
        historyClearButton.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
        startPage.addSubview(historyClearButton)

        historyEmptyLabel.font = UIFont.systemFont(ofSize: 12.5)
        historyEmptyLabel.textColor = Theme.secondary
        historyEmptyLabel.textAlignment = .center
        startPage.addSubview(historyEmptyLabel)

        historyGrid.backgroundColor = .clear
        historyGrid.dataSource = self
        historyGrid.delegate = self
        historyGrid.register(HistoryCell.self, forCellWithReuseIdentifier: "HistoryCell")
        startPage.addSubview(historyGrid)
        startPage.bringSubviewToFront(historyEmptyLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnStartPage))
        tap.cancelsTouchesInView = false
        startPage.addGestureRecognizer(tap)

        // 进度条挂在地址栏内部，始终压在最上层。
        addressField.bringSubviewToFront(progressBar)
    }

    private func layoutStartPageContent(webTop: CGFloat) {
        let width = view.bounds.width
        let height = view.bounds.height
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
        historyEmptyLabel.frame = CGRect(x: pad, y: histY + 40, width: contentWidth, height: 20)

        if let layout = historyGrid.collectionViewLayout as? UICollectionViewFlowLayout {
            let columns: CGFloat = 4
            let spacing: CGFloat = 12
            let cellW = floor((contentWidth - spacing * (columns - 1)) / columns)
            layout.itemSize = CGSize(width: cellW, height: 92)
            layout.minimumInteritemSpacing = spacing
            layout.minimumLineSpacing = 16
        }
        let gridY = histY + 32
        // 起始页坐标系的可用高度（不能再用整屏高度，否则宫格会溢出底部）。
        let pageHeight = max(0, height - webTop)
        historyGrid.frame = CGRect(x: pad, y: gridY, width: contentWidth, height: max(0, pageHeight - gridY - 16))
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
            iconView.tintColor = Theme.ink
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
        historyEmptyLabel.isHidden = !history.isEmpty
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
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = cleanTitle.isEmpty ? host : cleanTitle
        // 保存完整链接，从快捷入口返回时能直接回到原页面（也让地址栏有内容回填）。
        let entry = HistoryEntry(url: url.absoluteString, title: displayName, favicon: favicon)
        history.removeAll { registrableDomain(URL(string: $0.url)?.host ?? "") == domain }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit {
            history = Array(history.prefix(Self.historyLimit))
        }
        saveHistory()
        historyGrid.reloadData()
        historyEmptyLabel.isHidden = !history.isEmpty
    }

    @objc private func clearHistory() {
        history.removeAll()
        saveHistory()
        historyGrid.reloadData()
        historyEmptyLabel.isHidden = false
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
        guard let tab = currentTab else { return }
        if tab.isStartPage { return }
        tab.webView.reload()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === tabsSearchField {
            textField.resignFirstResponder()
            return true
        }
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
        tab.rawSWFs = []
        tab.verifiedSWFs = []
        tab.swfSizes = [:]
        tab.swfScores = [:]
        tab.title = ""
        tab.thumbnail = nil
        tab.progress = 0
        startPage.isHidden = true
        // 关键修复：从历史/快捷入口进来时，地址栏必须显示当前 URL。
        addressField.text = url.absoluteString
        updateSWFBadge()
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
        guard let web = currentTab?.webView, currentTab?.isStartPage == false else {
            backButton.isEnabled = false
            forwardButton.isEnabled = false
            backButton.alpha = 0.35
            forwardButton.alpha = 0.35
            return
        }
        backButton.isEnabled = web.canGoBack
        forwardButton.isEnabled = web.canGoForward
        backButton.alpha = web.canGoBack ? 1 : 0.35
        forwardButton.alpha = web.canGoForward ? 1 : 0.35
    }

    private func updateSWFBadge() {
        let count = currentTab?.verifiedSWFs.count ?? 0
        let hasAny = count > 0
        swfButton.isEnabled = hasAny || (currentTab?.rawSWFs.isEmpty == false)
        swfButton.alpha = 1
        var config = UIButton.Configuration.plain()
        // 抓到可播放的 SWF 时整枚角标转红（图标 + 数字），一眼能看出「有东西可下载」。
        config.image = UIImage(systemName: "bolt.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.imagePlacement = .leading
        config.imagePadding = hasAny ? 3 : 0
        config.baseForegroundColor = hasAny ? Theme.red : Theme.secondary
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        if hasAny {
            var title = AttributedString(count > 99 ? "99+" : String(count))
            title.font = UIFont.systemFont(ofSize: 12, weight: .bold)
            // 显式给颜色：AttributedString 不带 foregroundColor 时不保证跟随 baseForegroundColor。
            title.foregroundColor = Theme.red
            config.attributedTitle = title
        } else {
            config.attributedTitle = nil
        }
        swfButton.configuration = config
        swfButton.accessibilityLabel = hasAny
            ? L("browser.swfCount", String(count))
            : L("browser.swfNoneShort")

        // 位数变化时角标需要重新量宽度；布局期间不能反过来再触发一次布局。
        guard isViewLoaded, !isLayingOut else { return }
        let need = max(28, ceil(swfButton.sizeThatFits(CGSize(width: 260, height: 40)).width))
        if abs(need - swfButton.frame.width) > 0.5 { view.setNeedsLayout() }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === currentTab?.webView else { return }
        currentTab?.progress = 0.05
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === currentTab?.webView else { return }
        guard let tab = currentTab else { return }
        if let url = webView.url, url.absoluteString != "about:blank" {
            tab.url = url
            tab.isStartPage = false
            addressField.text = url.absoluteString
            startPage.isHidden = true
            updateNavButtons()
            // 抓取页面标题与 favicon 后记录历史。
            webView.evaluateJavaScript(Self.pageMetaScript) { [weak self, weak tab] result, _ in
                guard let self = self, let tab = tab,
                      let dict = result as? [String: Any] else { return }
                let title = dict["title"] as? String
                let icon = dict["icon"] as? String
                DispatchQueue.main.async {
                    tab.title = title ?? (url.host ?? "")
                    self.recordHistory(url, title: title, favicon: icon)
                    if self.tabsPanelVisible {
                        self.rebuildFilteredTabs()
                        self.tabsCollection.reloadData()
                    }
                }
            }
            scheduleThumbnailCapture(for: tab)
            requestSniff(for: tab)
        } else if webView.url?.absoluteString == "about:blank" {
            tab.isStartPage = true
            startPage.isHidden = false
            addressField.text = nil
            applyProgress(tab)
        }
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === currentTab?.webView else { return }
        finishProgress()
        updateNavButtons()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === currentTab?.webView else { return }
        finishProgress()
        updateNavButtons()
        let ns = error as NSError
        // 用户主动取消 / 被策略打断（如点了 SWF 下载）不弹提示。
        if ns.code == NSURLErrorCancelled || ns.code == 102 { return }
        showToast(L("browser.loadFailedTitle") + "：" + (ns.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === currentTab?.webView else { return }
        finishProgress()
        webView.reload()
    }

    /// 地址栏本身就是 .swf 直链时，不让 WKWebView 渲染，直接走下载播放流程。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if Self.isDirectSWF(url) {
            decisionHandler(.cancel)
            confirmDownload(url)
            return
        }
        // 非 http(s) 协议（mailto: / tel: / intent: …）交给系统，避免点击后毫无反应。
        let allowed: Set<String> = ["http", "https", "about", "file", "data", "blob", "javascript", ""]
        if !allowed.contains(scheme) {
            decisionHandler(.cancel)
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            return
        }
        // 兜底：某些站点用 target=_blank 但没触发 createWebViewWith，这里手动开新窗口。
        if navigationAction.targetFrame == nil, navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            if registerWindowRequest(url) { addTabAndSelect(load: url) }
            return
        }
        decisionHandler(.allow)
    }

    /// 防止 createWebViewWith 与 decidePolicy 同时触发时开出两个重复窗口。
    private var recentWindowRequests: [String: Date] = [:]

    private func registerWindowRequest(_ url: URL) -> Bool {
        let key = url.absoluteString
        let now = Date()
        if let last = recentWindowRequests[key], now.timeIntervalSince(last) < 1.2 { return false }
        recentWindowRequests[key] = now
        if recentWindowRequests.count > 24 { recentWindowRequests.removeAll() }
        return true
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

    // MARK: - WKUIDelegate（新窗口 / 脚本弹窗）

    /// 接管 target=_blank、window.open：原来没实现这个回调，点击后完全没反应。
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "about" else { return nil }
        if url.absoluteString == "about:blank" {
            addTabAndSelect(load: nil)
        } else if registerWindowRequest(url) {
            addTabAndSelect(load: url)
        }
        if tabsPanelVisible {
            rebuildFilteredTabs()
            tabsCollection.reloadData()
            updateTabsCount()
        }
        // 返回 nil：由我们自己的新窗口承载，WebKit 不再创建默认窗口。
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default) { _ in completionHandler() })
        presentAlert(alert, completionHandler: completionHandler)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default) { _ in completionHandler(true) })
        presentAlert(alert) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        presentAlert(alert) { completionHandler(nil) }
    }

    /// 避免弹窗期间控制器被 dismiss 导致 completionHandler 永不回调（页面卡死）。
    private func presentAlert(_ alert: UIAlertController, completionHandler: @escaping () -> Void) {
        guard presentedViewController == nil else {
            completionHandler()
            return
        }
        present(alert, animated: true)
    }

    // MARK: - SWF 嗅探（接收 → 校验 → 排序）

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "swfSniff",
              let body = message.body as? [String: Any],
              let web = message.webView,
              let tabIndex = tabs.firstIndex(where: { $0.webView === web }) else { return }

        var incoming: [(String, Int)] = []
        if let items = body["items"] as? [[String: Any]] {
            for item in items {
                guard let url = item["u"] as? String, !url.isEmpty else { continue }
                let score = (item["s"] as? NSNumber)?.intValue ?? 0
                incoming.append((url, score))
            }
        } else if let urls = body["urls"] as? [String] {
            incoming = urls.map { ($0, 0) }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.tabs.indices.contains(tabIndex) else { return }
            let tab = self.tabs[tabIndex]
            var changed = false
            for (url, score) in incoming {
                let key = Self.swfKey(url)
                if let existing = tab.rawSWFs.first(where: { Self.swfKey($0) == key }) {
                    if score > (tab.swfScores[existing] ?? 0) { tab.swfScores[existing] = score }
                } else {
                    tab.rawSWFs.append(url)
                    tab.swfScores[url] = score
                    changed = true
                }
            }
            guard changed || !tab.rawSWFs.isEmpty else { return }
            tab.rawSWFs.sort { (tab.swfScores[$0] ?? 0) > (tab.swfScores[$1] ?? 0) }
            if tabIndex == self.currentIndex { self.updateSWFBadge() }
            self.scheduleVerification(for: tab)
        }
    }

    /// 同一路径的 URL 视作同一个资源（忽略 query 差异）。
    private static func swfKey(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString.lowercased() }
        return ((url.host ?? "") + url.path).lowercased()
    }

    private var verifyWorkItems: [UUID: DispatchWorkItem] = [:]

    /// 主动让页面再跑一次嗅探（用于「重新嗅探」和 didFinish 后的补抓）。
    private func requestSniff(for tab: Tab) {
        tab.webView.evaluateJavaScript(Self.resniffScript, completionHandler: nil)
    }

    private func scheduleVerification(for tab: Tab) {
        verifyWorkItems[tab.id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak tab] in
            guard let self = self, let tab = tab else { return }
            self.verifyCandidates(for: tab)
        }
        verifyWorkItems[tab.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// 用 Range 请求探测前几个字节，只保留真正返回 SWF 的候选，
    /// 避免把 404 页面、广告壳、无关 swf 混进列表（用户反馈「提示缺少文件」多来自这些）。
    private func verifyCandidates(for tab: Tab) {
        guard !tab.isVerifying else { return }
        let candidates = Array(tab.rawSWFs.prefix(10))
        guard !candidates.isEmpty else { return }
        tab.isVerifying = true
        var passed: [String: Int] = [:]
        let group = DispatchGroup()
        let lock = NSLock()
        for candidate in candidates {
            group.enter()
            probeSWF(candidate, referer: tab.url) { ok, size in
                if ok {
                    lock.lock()
                    passed[candidate] = size ?? 0
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self, weak tab] in
            guard let self = self, let tab = tab else { return }
            tab.isVerifying = false
            // 保持原始置信度顺序。
            tab.verifiedSWFs = candidates.filter { passed[$0] != nil }
            tab.swfSizes = passed
            if tab === self.currentTab { self.updateSWFBadge() }
            if self.tabsPanelVisible { self.tabsCollection.reloadData() }
            if self.pendingShowSWFList && tab === self.currentTab {
                self.pendingShowSWFList = false
                if !tab.verifiedSWFs.isEmpty { self.presentSWFList() }
            }
        }
    }

    private func probeSWF(_ urlString: String, referer: URL?,
                          completion: @escaping (Bool, Int?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(false, nil)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.refererHeader(referer, fallback: url), forHTTPHeaderField: "Referer")
        request.setValue("bytes=0-63", forHTTPHeaderField: "Range")
        URLSession.shared.dataTask(with: request) { data, response, error in
            var ok = false
            var size: Int?
            if let http = response as? HTTPURLResponse, error == nil {
                if let range = http.value(forHTTPHeaderField: "Content-Range"),
                   let total = range.split(separator: "/").last.flatMap({ Int($0) }) {
                    size = total
                } else if http.expectedContentLength > 0 {
                    size = Int(http.expectedContentLength)
                }
                let statusOK = (200..<300).contains(http.statusCode) || http.statusCode == 416
                let mime = (http.mimeType ?? "").lowercased()
                if statusOK, let data = data, data.count >= 3 {
                    let signature = String(decoding: data.prefix(3), as: UTF8.self)
                    ok = ["FWS", "CWS", "ZWS"].contains(signature)
                }
                if !ok, statusOK, mime.contains("shockwave") { ok = true }
                if http.statusCode == 416, mime.contains("shockwave") { ok = true }
            }
            DispatchQueue.main.async { completion(ok, size) }
        }.resume()
    }

    private static func refererHeader(_ referer: URL?, fallback: URL) -> String {
        let url = referer ?? fallback
        return "\(url.scheme ?? "https")://\(url.host ?? "")/"
    }

    @objc private func showDetectedSWFs() {
        guard let tab = currentTab else { return }
        if tab.isVerifying && tab.verifiedSWFs.isEmpty {
            pendingShowSWFList = true
            showToast(L("browser.verifying"))
            return
        }
        if tab.verifiedSWFs.isEmpty && tab.rawSWFs.isEmpty {
            showError(L("browser.swfNone"))
            return
        }
        presentSWFList()
    }

    private func presentSWFList() {
        guard let tab = currentTab else { return }
        // 优先展示校验通过的资源；全部没通过时退化为原始候选（有些站点不支持 Range/防盗链）。
        let list = tab.verifiedSWFs.isEmpty ? tab.rawSWFs : tab.verifiedSWFs
        guard !list.isEmpty else {
            showError(L("browser.swfNone"))
            return
        }
        let sheet = UIAlertController(title: L("browser.swfListTitle"),
                                      message: L("browser.swfListMessage", String(list.count)),
                                      preferredStyle: .actionSheet)
        for (index, value) in list.enumerated() {
            let name = (value as NSString).lastPathComponent
            let host = URL(string: value)?.host ?? ""
            var label = "\(index + 1). \(name)"
            if let bytes = tab.swfSizes[value], bytes > 0 {
                label += "  ·  " + Self.sizeText(bytes)
            } else if !host.isEmpty {
                label += "  ·  " + host
            }
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                guard let self = self, let url = URL(string: value) else { return }
                self.confirmDownload(url)
            })
        }
        sheet.addAction(UIAlertAction(title: L("browser.swfRescan"), style: .default) { [weak self] _ in
            guard let self = self, let tab = self.currentTab else { return }
            tab.verifiedSWFs = []
            tab.rawSWFs = []
            tab.swfScores = [:]
            self.updateSWFBadge()
            tab.webView.evaluateJavaScript(Self.resniffScript, completionHandler: nil)
            self.showToast(L("browser.verifying"))
        })
        sheet.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = swfButton
            popover.sourceRect = swfButton.bounds
        }
        present(sheet, animated: true)
    }

    private static func sizeText(_ bytes: Int) -> String {
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
        }
        return String(format: "%d KB", max(1, bytes / 1024))
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
        request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.refererHeader(refererBase, fallback: url), forHTTPHeaderField: "Referer")

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

    // MARK: - 截图缩略图

    private func scheduleThumbnailCapture(for tab: Tab) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self, weak tab] in
            guard let self = self, let tab = tab, !tab.isStartPage else { return }
            self.captureThumbnail(for: tab)
        }
    }

    private func captureThumbnail(for tab: Tab) {
        guard tab.webView.bounds.width > 0, tab.webView.superview != nil else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 340
        tab.webView.takeSnapshot(with: config) { [weak self, weak tab] image, _ in
            guard let self = self, let tab = tab, let image = image else { return }
            tab.thumbnail = image
            guard self.tabsPanelVisible,
                  let item = self.filteredIndices.firstIndex(of: self.tabs.firstIndex(where: { $0 === tab }) ?? -1) else { return }
            let indexPath = IndexPath(item: item, section: 0)
            if self.tabsCollection.indexPathsForVisibleItems.contains(indexPath) {
                UIView.performWithoutAnimation {
                    self.tabsCollection.reloadItems(at: [indexPath])
                }
            }
        }
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
        UIView.animate(withDuration: 0.3, delay: 2.6, options: .curveEaseInOut, animations: {
            label.alpha = 0
        }, completion: { _ in label.removeFromSuperview() })
    }

    // MARK: - UICollectionView 数据源

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === historyGrid { return history.count }
        if collectionView === tabsCollection { return filteredIndices.count }
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
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TabCardCell", for: indexPath) as! TabCardCell
        guard filteredIndices.indices.contains(indexPath.item) else { return cell }
        let tabIndex = filteredIndices[indexPath.item]
        guard tabs.indices.contains(tabIndex) else { return cell }
        let tab = tabs[tabIndex]
        cell.configure(title: tab.displayTitle,
                       host: tab.host,
                       thumbnail: tab.thumbnail,
                       isCurrent: tabIndex == currentIndex)
        cell.onClose = { [weak self] in
            self?.animateCloseTab(at: tabIndex)
        }
        // 卡片入场：轻微缩放 + 逐个错峰。
        if staggerCells {
            cell.alpha = 0
            cell.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            UIView.animate(withDuration: 0.32,
                           delay: min(0.16, Double(indexPath.item) * 0.035),
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0.2,
                           options: [.curveEaseOut],
                           animations: {
                cell.alpha = 1
                cell.transform = .identity
            })
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard collectionView === tabsCollection else {
            return (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? .zero
        }
        let insets = view.safeAreaInsets
        let available = view.bounds.width - insets.left - insets.right - 32 - 14
        let cellW = floor(available / 2)
        return CGSize(width: cellW, height: floor(cellW * 1.18) + 33)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === historyGrid {
            guard history.indices.contains(indexPath.item),
                  let url = normalizedURL(history[indexPath.item].url) else { return }
            addressField.resignFirstResponder()
            loadCurrentTab(url)
        } else if collectionView === tabsCollection {
            guard filteredIndices.indices.contains(indexPath.item) else { return }
            let tabIndex = filteredIndices[indexPath.item]
            guard let cell = collectionView.cellForItem(at: indexPath) as? TabCardCell else {
                selectTab(at: tabIndex)
                return
            }
            // 卡片按压回弹 → 关闭面板 → 内容淡入。
            UIView.animate(withDuration: 0.11, delay: 0, options: .curveEaseIn, animations: {
                cell.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            }, completion: { _ in
                UIView.animate(withDuration: 0.13, animations: {
                    cell.transform = .identity
                }, completion: { _ in
                    self.selectTab(at: tabIndex)
                })
            })
        }
    }

    private func animateCloseTab(at index: Int) {
        guard tabs.count > 1 else {
            showToast(L("browser.lastTabHint"))
            return
        }
        guard let position = filteredIndices.firstIndex(of: index),
              let cell = tabsCollection.cellForItem(at: IndexPath(item: position, section: 0)) else {
            closeTab(at: index)
            return
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseIn, animations: {
            cell.alpha = 0
            cell.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }, completion: { _ in
            guard self.removeTabModel(at: index) else { return }
            self.rebuildFilteredTabs()
            self.attachCurrentWebView()
            self.updateUIForCurrentTab()
            UIView.performWithoutAnimation { self.tabsCollection.reloadData() }
            self.updateTabsCount()
            UIView.animate(withDuration: 0.22, animations: {
                self.tabsCollection.collectionViewLayout.invalidateLayout()
            })
        })
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

    /// 嗅探页面中的 SWF 资源，并按「更像主游戏文件」的程度打分：
    ///  - embed / object / param 优先（真正的挂载点）
    ///  - JS 字符串字面量（如 oldswf 的 loadSwf("/data/game_2024/74536.swf")）
    ///  - data-* 属性、a[href]、iframe[src]
    ///  - 广告/统计类、加载器壳、图标音效类降权，交给原生侧再按 Range 探测二次过滤
    static let sniffScript = #"""
    (function () {
      if (window.__swfSniffInstalled) { return; }
      window.__swfSniffInstalled = true;

      var AD = /(^|[^a-z0-9])(ads?|adserver|advert\w*|banner\w*|promo\w*|sponsor\w*|tracking|tracker|analytics|stats|pixel|beacon|doubleclick|googlesyndication|adsense|adservice|popunder|popup|union)([^a-z0-9]|$)/i;
      var SHELL = /(preload|preloader|loader|loading|splash|placeholder|blank|spacer|transparent|footer|header|logo|button|icon|thumb|avatar|sound|music|bgm|skin|shield)([^a-z0-9]|$)/i;
      var GOOD = /(game|play|main|start|index|movie|flash|swf)([^a-z0-9]|$)/i;

      function abs(u) {
        try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
      }

      function collect() {
        var scored = {};
        var order = [];

        function add(raw, base) {
          if (!raw) { return; }
          var s = String(raw).trim();
          if (!s || /^data:/i.test(s) || /^blob:/i.test(s)) { return; }
          var full = abs(s);
          if (!full || !/^https?:\/\//i.test(full)) { return; }
          if (!/\.swf(\?|#|$)/i.test(full)) { return; }
          var clean = full.split('#')[0];
          var key;
          try {
            var u = new URL(clean);
            key = (u.host + u.pathname).toLowerCase();
          } catch (e) { key = clean.toLowerCase(); }
          if (!scored[key]) { scored[key] = { u: clean, s: 0 }; order.push(key); }
          if (base > scored[key].s) { scored[key].s = base; }
        }

        // 1) 真正的挂载点
        var embeds = document.querySelectorAll('embed[src]');
        for (var i = 0; i < embeds.length; i++) { add(embeds[i].getAttribute('src'), 62); }
        var objects = document.querySelectorAll('object[data], object[codebase]');
        for (var o = 0; o < objects.length; o++) {
          add(objects[o].getAttribute('data'), 58);
          add(objects[o].getAttribute('codebase'), 30);
        }
        var params = document.querySelectorAll('param[name][value]');
        for (var p = 0; p < params.length; p++) {
          var pn = (params[p].getAttribute('name') || '').toLowerCase();
          if (pn === 'movie' || pn === 'src' || pn === 'data') { add(params[p].getAttribute('value'), 56); }
          else if (pn === 'flashvars') {
            var fv = params[p].getAttribute('value') || '';
            var fre = /(?:^|[&?])\w*(?:url|file|swf|src)\w*=([^&]+)/gi, fm;
            while ((fm = fre.exec(fv)) !== null) {
              try { add(decodeURIComponent(fm[1]), 44); } catch (e) { add(fm[1], 40); }
            }
          }
        }

        // 2) data-* 挂载属性
        var dataNodes = document.querySelectorAll('[data-src],[data-file],[data-swf],[data-movie],[data-url]');
        for (var d = 0; d < dataNodes.length; d++) {
          var attrs = ['data-src', 'data-file', 'data-swf', 'data-movie', 'data-url'];
          for (var a = 0; a < attrs.length; a++) { add(dataNodes[d].getAttribute(attrs[a]), 42); }
        }

        // 3) 链接 / iframe / 输入框
        var links = document.querySelectorAll('a[href],area[href]');
        for (var l = 0; l < links.length; l++) { add(links[l].getAttribute('href'), 24); }
        var frames = document.querySelectorAll('iframe[src]');
        for (var f = 0; f < frames.length; f++) { add(frames[f].getAttribute('src'), 16); }
        var inputs = document.querySelectorAll('input[value]');
        for (var n = 0; n < inputs.length; n++) { add(inputs[n].getAttribute('value'), 18); }

        // 4) 整个文档 HTML 里带属性形式的 .swf
        try {
          var html = document.documentElement.outerHTML;
          // 超大页面跳过整页正则，避免长时间占用主线程把页面点击卡死。
          if (html.length < 600000) {
            var re = /(?:src|data|value|href|movie|url)\s*=\s*["'][^"']*?\.swf(?:\?[^"']*)?["']/gi;
            var m;
            while ((m = re.exec(html)) !== null) {
              var q = m[0].indexOf('=');
              var v = m[0].substring(q + 1).trim().replace(/^["']|["']$/g, '');
              add(v, 34);
            }
          }
        } catch (e) {}

        // 5) JS 字符串字面量里的 .swf（oldswf 等站点把真实文件写在脚本里）
        try {
          var scripts = document.querySelectorAll('script');
          var stre = /(["'`])([^"'`\s]*?\.swf(?:\?[^"'`\s]*)?)\1/gi;
          for (var s = 0; s < scripts.length; s++) {
            var text = scripts[s].textContent || '';
            var sm;
            while ((sm = stre.exec(text)) !== null) { add(sm[2], 46); }
          }
        } catch (e) {}

        // 6) 纯文本里裸露的 .swf 路径
        try {
          var bodyText = document.body ? document.body.innerHTML : '';
          if (bodyText.length < 600000) {
            var bare = /([^\s"'<>()]{2,}?\.swf(?:\?[^\s"'<>]*)?)/gi;
            var bm;
            while ((bm = bare.exec(bodyText)) !== null) { add(bm[1], 20); }
          }
        } catch (e) {}

        var pageHost = '';
        try { pageHost = document.location.host.toLowerCase(); } catch (e) {}

        var out = [];
        for (var k = 0; k < order.length; k++) {
          var item = scored[order[k]];
          if (!item) { continue; }
          var path = '';
          var host = '';
          try { var uu = new URL(item.u); path = uu.pathname; host = uu.host.toLowerCase(); } catch (e) {}
          var score = item.s;
          if (AD.test(item.u)) { score -= 260; }
          if (SHELL.test(path)) { score -= 42; }
          if (GOOD.test(path)) { score += 12; }
          if (path.split('/').length >= 4) { score += 8; }
          if (host === pageHost) { score += 14; }
          if (score <= -100) { continue; }
          out.push({ u: item.u, s: score });
        }

        out.sort(function (a, b) {
          if (b.s !== a.s) { return b.s - a.s; }
          return a.u.length - b.u.length;
        });
        return out.slice(0, 20);
      }

      var lastReportAt = 0;
      var lastSignature = '';
      var pendingReport = null;
      function report() {
        var now = Date.now();
        // 节流：同一页面反复扫描会拖慢渲染，导致点击/跳转像「卡住」一样无响应。
        if (now - lastReportAt < 700) {
          if (!pendingReport) {
            pendingReport = setTimeout(function () { pendingReport = null; report(); }, 780);
          }
          return;
        }
        lastReportAt = now;
        try {
          var items = collect();
          var sig = '';
          for (var i = 0; i < items.length; i++) { sig += items[i].u + '|'; }
          if (sig === lastSignature) { return; }
          lastSignature = sig;
          window.webkit.messageHandlers.swfSniff.postMessage({ items: items });
        } catch (e) {}
      }
      window.__swfSniff = report;

      function boot() {
        setTimeout(report, 260);
        setTimeout(report, 1200);
        setTimeout(report, 2600);
      }
      if (document.readyState === 'complete' || document.readyState === 'interactive') {
        boot();
      } else {
        document.addEventListener('DOMContentLoaded', boot);
      }
      window.addEventListener('load', function () { setTimeout(report, 400); });
      window.addEventListener('pageshow', function () { setTimeout(report, 400); });

      if (window.MutationObserver) {
        var timer = null;
        var observer = new MutationObserver(function () {
          if (timer) { return; }
          timer = setTimeout(function () { timer = null; report(); }, 1100);
        });
        try {
          // 只听结构变化；监听 attributes 会让动画/滚动类页面高频触发，拖慢点击响应。
          observer.observe(document.documentElement || document,
                           { childList: true, subtree: true });
        } catch (e) {}
      }
    })();
    """#

    /// 页面重载后主动再抓一次（供给用户点「重新嗅探」）。
    static let resniffScript = "window.__swfSniff && window.__swfSniff();"
}
