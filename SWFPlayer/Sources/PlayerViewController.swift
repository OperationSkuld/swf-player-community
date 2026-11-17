import UIKit
import WebKit

/// 播放页 chrome 布局：
/// 顶部 7 个圆形按钮 —— 返回 / 横竖屏 / 截图 / 播放详情 / HQ / 平铺 / 字体；
/// 底部胶囊 4 项 —— 重载 / 播放暂停 / 亮度 / 声音。
final class PlayerViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    private var item: SWFItem
    private var webView: WKWebView!

    private let topBar = UIView()
    private let bottomBar = UIView()

    /// 暂停时画面中央的精致播放键：替代被隐藏的 Ruffle 原生大橙圆，
    /// 点击即可继续播放。只覆盖中间一小块，不挡整屏。
    private let centerPlayButton = UIButton(type: .system)

    private let backButton = UIButton(type: .system)
    private let orientationButton = UIButton(type: .system)
    private let snapshotButton = UIButton(type: .system)
    private let infoButton = UIButton(type: .system)
    private let hqButton = UIButton(type: .system)
    private let stretchButton = UIButton(type: .system)
    private let fontButton = UIButton(type: .system)

    private let reloadButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let brightnessIcon = UIImageView()
    private let brightnessSlider = UISlider()
    private let speakerButton = UIButton(type: .system)
    private let volumeSlider = UISlider()

    private let statusLabel = UILabel()

    private let errorOverlay = UIView()
    private let errorCard = UIView()
    private let errorTitleLabel = UILabel()
    private let errorBodyLabel = UILabel()
    private let errorRetryButton = UIButton(type: .system)
    private let errorBackButton = UIButton(type: .system)

    private let infoOverlay = UIView()
    private let infoCard = UIView()
    private let infoTitleLabel = UILabel()
    private let infoRowsStack = UIStackView()
    private let infoCloseButton = UIButton(type: .system)
    private var infoTap: UITapGestureRecognizer?

    private var isPlaying = true
    private var isMuted = false
    private var isHQ = true
    private var isStretched = false
    private var volume: Float = 0.8
    private var didRetryWithData = false
    private var didReceiveReady = false
    private var metadata: [String: Any] = [:]

    /// 播放时控件会自动淡出，避免遮挡画面；只有点上/下两条热区才会切换显隐，
    /// 中间大片区域留给游戏，避免玩的时候误触把控件叫出来。
    private var chromeVisible = true
    private var autoHideWorkItem: DispatchWorkItem?
    private var chromeTap: UITapGestureRecognizer?

    private var topButtons: [UIButton] {
        [backButton, orientationButton, snapshotButton, infoButton, hqButton, stretchButton, fontButton]
    }

    init(item: SWFItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        autoHideWorkItem?.cancel()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "bridge")
        OrientationManager.allowLandscape = false
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.playerBlack
        navigationController?.setNavigationBarHidden(true, animated: false)

        isMuted = PlaybackPreferences.startMuted
        isPlaying = PlaybackPreferences.autoPlay
        volume = isMuted ? 0 : 0.8

        webView = PlayerWebViewFactory.make(messageHandler: self)
        webView.navigationDelegate = self
        view.addSubview(webView)

        // 显隐热区：只有顶部 / 底部两条窄带里的点击才切换控件。
        // 挂在 self.view 上而不是 webView 上，这样控件显示时点条带空白处也能收起。
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleChromeZoneTap))
        tap.cancelsTouchesInView = true
        tap.delegate = self
        view.addGestureRecognizer(tap)
        chromeTap = tap

        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)

        buildTopBar()
        buildBottomBar()
        buildCenterPlayButton()
        buildErrorOverlay()
        buildInfoOverlay()

        applyLocalization()
        applyTextScale()
        updatePlayButton()
        updateSpeaker()
        updateOptionIndicators()

        let page = PlayerURL.pageURL(autoplay: PlaybackPreferences.autoPlay,
                                     muted: PlaybackPreferences.startMuted)
        webView.load(URLRequest(url: page, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        brightnessSlider.value = Float(currentScreen.brightness)
        volumeSlider.value = isMuted ? 0 : volume
        showChrome(animated: false)
        scheduleAutoHide()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        autoHideWorkItem?.cancel()
        OrientationManager.allowLandscape = false
        requestOrientationUpdate()
    }

    // MARK: - 控件显隐

    private func scheduleAutoHide() {
        autoHideWorkItem?.cancel()
        guard isPlaying, errorOverlay.isHidden else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPlaying, self.errorOverlay.isHidden else { return }
            self.hideChrome()
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    private func showChrome(animated: Bool = true) {
        guard !chromeVisible || topBar.alpha < 1 else {
            scheduleAutoHide()
            return
        }
        chromeVisible = true
        topBar.isUserInteractionEnabled = true
        bottomBar.isUserInteractionEnabled = true
        let apply = {
            self.topBar.alpha = 1
            self.bottomBar.alpha = 1
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: apply)
        } else {
            apply()
        }
        scheduleAutoHide()
    }

    private func hideChrome(animated: Bool = true) {
        guard chromeVisible else { return }
        chromeVisible = false
        autoHideWorkItem?.cancel()
        topBar.isUserInteractionEnabled = false
        bottomBar.isUserInteractionEnabled = false
        let apply = {
            self.topBar.alpha = 0
            self.bottomBar.alpha = 0
        }
        if animated {
            UIView.animate(withDuration: 0.24, animations: apply)
        } else {
            apply()
        }
    }

    /// 只有落在上/下热区里的点击才算「切显隐」，其它位置的触摸完全不拦截游戏。
    @objc private func handleChromeZoneTap() {
        if chromeVisible {
            hideChrome()
        } else {
            showChrome()
        }
    }

    /// 热区只有两块：上排按钮条 + 下排胶囊（各外扩几 pt 方便手指）。
    /// 屏幕中间的大片区域完全不参与显隐，横竖屏都不会误触。
    private func chromeHitZones() -> [CGRect] {
        guard topBar.frame.height > 0, bottomBar.frame.height > 0 else { return [] }
        let bounds = view.bounds
        let top = topBar.frame.insetBy(dx: -8, dy: -8).intersection(bounds)
        let bottom = bottomBar.frame.insetBy(dx: -10, dy: -10).intersection(bounds)
        return [top, bottom].filter { !$0.isEmpty }
    }

    /// 点到按钮/滑杆（UIControl）本身时交给控件，不要顺带切换显隐；
    /// 点在上下条的空白处则是「收起 / 唤出」。
    private func isChromeControlHit(_ hit: UIView) -> Bool {
        var node: UIView? = hit
        while let current = node {
            if current is UIControl { return true }
            node = current.superview
        }
        return false
    }

    /// 任何控件交互都会重置自动隐藏计时，拖滑杆时控件不会中途消失。
    private func keepChromeAlive() {
        showChrome()
    }

    private func requestOrientationUpdate() {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private var currentScreen: UIScreen {
        view.window?.screen ?? UIScreen.main
    }

    // MARK: - 控件构建

    private func buildTopBar() {
        topBar.backgroundColor = .clear
        view.addSubview(topBar)

        configureTop(backButton,
                     image: PlayerGlyph.symbol(["chevron.left"], pointSize: 16, weight: .bold),
                     label: L("player.back"),
                     action: #selector(goBack))
        configureTop(orientationButton,
                     image: PlayerGlyph.symbol(["rectangle.landscape.rotate",
                                                "rectangle.portrait.rotate",
                                                "rotate.right"], pointSize: 16),
                     label: L("player.rotate"),
                     action: #selector(toggleOrientation))
        configureTop(snapshotButton,
                     image: PlayerGlyph.symbol(["camera.fill"], pointSize: 15),
                     label: L("player.snapshot"),
                     action: #selector(takeScreenshot))
        configureTop(infoButton,
                     image: PlayerGlyph.symbol(["info"], pointSize: 16),
                     label: L("player.info"),
                     action: #selector(showInfo))
        configureTop(hqButton,
                     image: PlayerGlyph.text("HQ", fontSize: 12.5),
                     label: L("player.quality"),
                     action: #selector(toggleHQ))
        configureTop(stretchButton,
                     image: PlayerGlyph.symbol(["arrow.up.left.and.arrow.down.right"], pointSize: 13.5),
                     label: L("player.stretch"),
                     action: #selector(toggleStretch))
        configureTop(fontButton,
                     image: PlayerGlyph.text("Tt", fontSize: 14),
                     label: L("player.textSize"),
                     action: #selector(chooseTextScale))
    }

    private func configureTop(_ button: UIButton, image: UIImage?, label: String, action: Selector) {
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.backgroundColor = Theme.playerCircle
        button.clipsToBounds = true
        button.contentVerticalAlignment = .center
        button.contentHorizontalAlignment = .center
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        topBar.addSubview(button)
    }

    private func buildBottomBar() {
        bottomBar.backgroundColor = Theme.playerPill
        bottomBar.layer.cornerRadius = 34
        view.addSubview(bottomBar)

        reloadButton.setImage(PlayerGlyph.symbol(["arrow.clockwise"], pointSize: 15, weight: .semibold),
                              for: .normal)
        reloadButton.tintColor = .white
        reloadButton.contentVerticalAlignment = .center
        reloadButton.contentHorizontalAlignment = .center
        reloadButton.accessibilityLabel = L("player.reload")
        reloadButton.addTarget(self, action: #selector(reloadMovie), for: .touchUpInside)
        bottomBar.addSubview(reloadButton)

        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        bottomBar.addSubview(playButton)

        brightnessIcon.image = PlayerGlyph.symbol(["sun.max.fill"], pointSize: 11, weight: .semibold)?
            .withTintColor(UIColor.white.withAlphaComponent(0.72), renderingMode: .alwaysOriginal)
        brightnessIcon.contentMode = .scaleAspectFit
        bottomBar.addSubview(brightnessIcon)

        brightnessSlider.minimumValue = 0.05
        brightnessSlider.maximumValue = 1
        brightnessSlider.value = 1
        brightnessSlider.minimumTrackTintColor = Theme.playerAccent
        brightnessSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.26)
        brightnessSlider.thumbTintColor = .white
        brightnessSlider.accessibilityLabel = L("player.brightness")
        brightnessSlider.addTarget(self, action: #selector(brightnessChanged(_:)), for: .valueChanged)
        bottomBar.addSubview(brightnessSlider)

        speakerButton.tintColor = .white
        speakerButton.contentVerticalAlignment = .center
        speakerButton.contentHorizontalAlignment = .center
        speakerButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        bottomBar.addSubview(speakerButton)

        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.value = isMuted ? 0 : volume
        volumeSlider.minimumTrackTintColor = .white
        volumeSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.26)
        volumeSlider.thumbTintColor = .white
        volumeSlider.accessibilityLabel = L("player.volume")
        volumeSlider.addTarget(self, action: #selector(volumeChanged(_:)), for: .valueChanged)
        bottomBar.addSubview(volumeSlider)
    }

    private func buildCenterPlayButton() {
        // 半透明深色圆 + 白色播放三角，小巧精致，与原版简洁风格一致。
        centerPlayButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        centerPlayButton.tintColor = .white
        centerPlayButton.layer.cornerRadius = 34
        centerPlayButton.clipsToBounds = true
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        centerPlayButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        centerPlayButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        centerPlayButton.accessibilityLabel = L("player.play")
        centerPlayButton.addTarget(self, action: #selector(centerPlayTapped), for: .touchUpInside)
        centerPlayButton.isHidden = true
        view.addSubview(centerPlayButton)
    }

    private func buildErrorOverlay() {
        errorOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        errorOverlay.isHidden = true
        errorOverlay.alpha = 0
        view.addSubview(errorOverlay)

        errorCard.backgroundColor = Theme.playerPill
        errorCard.layer.cornerRadius = 22
        errorOverlay.addSubview(errorCard)

        errorTitleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        errorTitleLabel.textColor = .white
        errorTitleLabel.textAlignment = .center
        errorTitleLabel.numberOfLines = 0
        errorCard.addSubview(errorTitleLabel)

        errorBodyLabel.font = UIFont.systemFont(ofSize: 13)
        errorBodyLabel.textColor = UIColor.white.withAlphaComponent(0.66)
        errorBodyLabel.textAlignment = .center
        errorBodyLabel.numberOfLines = 0
        errorCard.addSubview(errorBodyLabel)

        style(errorButton: errorRetryButton, background: Theme.red, foreground: .white)
        errorRetryButton.addTarget(self, action: #selector(retryPlayback), for: .touchUpInside)
        errorCard.addSubview(errorRetryButton)

        style(errorButton: errorBackButton,
              background: UIColor.white.withAlphaComponent(0.14),
              foreground: .white)
        errorBackButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        errorCard.addSubview(errorBackButton)
    }

    private func style(errorButton button: UIButton, background: UIColor, foreground: UIColor) {
        button.backgroundColor = background
        button.setTitleColor(foreground, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 13
        button.clipsToBounds = true
    }

    private func buildInfoOverlay() {
        infoOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        infoOverlay.isHidden = true
        infoOverlay.alpha = 0
        view.addSubview(infoOverlay)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissInfo))
        tap.delegate = self
        infoOverlay.addGestureRecognizer(tap)
        infoTap = tap

        infoCard.translatesAutoresizingMaskIntoConstraints = false
        infoCard.backgroundColor = Theme.playerPill
        infoCard.layer.cornerRadius = 22
        infoOverlay.addSubview(infoCard)

        infoTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        infoTitleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        infoTitleLabel.textColor = .white
        infoTitleLabel.numberOfLines = 0
        infoCard.addSubview(infoTitleLabel)

        infoRowsStack.translatesAutoresizingMaskIntoConstraints = false
        infoRowsStack.axis = .vertical
        infoRowsStack.spacing = 9
        infoRowsStack.alignment = .fill
        infoCard.addSubview(infoRowsStack)

        infoCloseButton.translatesAutoresizingMaskIntoConstraints = false
        infoCloseButton.setTitleColor(.white, for: .normal)
        infoCloseButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        infoCloseButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        infoCloseButton.layer.cornerRadius = 13
        infoCloseButton.clipsToBounds = true
        infoCloseButton.addTarget(self, action: #selector(dismissInfo), for: .touchUpInside)
        infoCard.addSubview(infoCloseButton)

        let preferredWidth = infoCard.widthAnchor.constraint(equalToConstant: 340)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            infoCard.centerXAnchor.constraint(equalTo: infoOverlay.centerXAnchor),
            infoCard.centerYAnchor.constraint(equalTo: infoOverlay.centerYAnchor),
            preferredWidth,
            infoCard.leadingAnchor.constraint(greaterThanOrEqualTo: infoOverlay.leadingAnchor, constant: 24),

            infoTitleLabel.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 22),
            infoTitleLabel.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 22),
            infoTitleLabel.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -22),

            infoRowsStack.topAnchor.constraint(equalTo: infoTitleLabel.bottomAnchor, constant: 14),
            infoRowsStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 22),
            infoRowsStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -22),

            infoCloseButton.topAnchor.constraint(equalTo: infoRowsStack.bottomAnchor, constant: 20),
            infoCloseButton.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 22),
            infoCloseButton.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -22),
            infoCloseButton.heightAnchor.constraint(equalToConstant: 44),
            infoCloseButton.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -22)
        ])
    }

    // MARK: - 本地化与状态

    private func applyLocalization() {
        backButton.accessibilityLabel = L("player.back")
        orientationButton.accessibilityLabel = L("player.rotate")
        snapshotButton.accessibilityLabel = L("player.snapshot")
        infoButton.accessibilityLabel = L("player.info")
        hqButton.accessibilityLabel = L("player.quality")
        stretchButton.accessibilityLabel = L("player.stretch")
        fontButton.accessibilityLabel = L("player.textSize")
        reloadButton.accessibilityLabel = L("player.reload")
        brightnessSlider.accessibilityLabel = L("player.brightness")
        speakerButton.accessibilityLabel = isMuted ? L("player.unmute") : L("player.mute")
        statusLabel.text = L("player.loading")
        errorTitleLabel.text = L("player.loadFailedTitle")
        errorBodyLabel.text = L("player.runtimeHint")
        errorRetryButton.setTitle(L("player.retryAction"), for: .normal)
        errorBackButton.setTitle(L("player.back"), for: .normal)
        infoTitleLabel.text = L("player.infoTitle")
        infoCloseButton.setTitle(L("player.infoClose"), for: .normal)
        updatePlayButton()
    }

    private func applyTextScale() {
        let scale = PlaybackPreferences.textScale.multiplier
        statusLabel.font = UIFont.systemFont(ofSize: 13 * scale)
        for case let label as UILabel in infoRowsStack.arrangedSubviews {
            label.font = UIFont.systemFont(ofSize: 13.5 * scale)
        }
    }

    private func updatePlayButton() {
        // 白色实心圆 + 深色符号，与原版一致；用 Configuration 给播放三角做轻微
        // 光学右移（三角形视觉重心天然偏左），暂停的双竖条则保持严格居中。
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .white
        config.baseForegroundColor = Theme.ink
        config.cornerStyle = .capsule
        // 只在真正需要时给三角右移 ~1pt，避免符号过大、过偏。
        config.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                       leading: isPlaying ? 0 : 1.5,
                                                       bottom: 0,
                                                       trailing: isPlaying ? 0 : 1.5)
        let symbol = isPlaying ? "pause.fill" : "play.fill"
        config.image = UIImage(systemName: symbol,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        playButton.configuration = config
        playButton.accessibilityLabel = isPlaying ? L("player.pause") : L("player.play")
        // 暂停时显示中央播放键；播放时隐藏，让画面保持干净。
        centerPlayButton.isHidden = isPlaying
    }

    private func updateSpeaker() {
        let name: String
        if isMuted || volume < 0.01 {
            name = "speaker.slash.fill"
        } else if volume < 0.5 {
            name = "speaker.wave.1.fill"
        } else {
            name = "speaker.wave.2.fill"
        }
        let image = PlayerGlyph.symbol([name], pointSize: 12.5, weight: .semibold)
        speakerButton.setImage(image, for: .normal)
        speakerButton.accessibilityLabel = isMuted ? L("player.unmute") : L("player.mute")
    }

    /// HQ / 平铺 处于开启态时保持满不透明，关闭态变暗，符合参考图的"激活感"。
    private func updateOptionIndicators() {
        hqButton.alpha = isHQ ? 1.0 : 0.55
        stretchButton.alpha = isStretched ? 1.0 : 0.55
    }

    // MARK: - 布局

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = view.bounds.width
        let height = view.bounds.height
        let insets = view.safeAreaInsets
        let safeTop = insets.top
        let safeBottom = insets.bottom
        let landscape = width > height
        webView.frame = view.bounds

        // 顶部：直径按可用宽度收敛，7 个圆钮永远排成一行且不越界。
        // 注意：按钮是 topBar 的子视图，必须使用 topBar 本地坐标（y 从 0 起算），
        // 否则会因超出父视图 bounds 而完全收不到触摸事件。
        let sideMargin = max(14, insets.left + 8)
        let sideMarginRight = max(14, insets.right + 8)
        let spacing: CGFloat = 6
        let count = CGFloat(topButtons.count)
        let available = width - sideMargin - sideMarginRight
        let maxDiameter: CGFloat = landscape ? 38 : 44
        let diameter = min(maxDiameter, floor((available - spacing * (count - 1)) / count))
        let totalWidth = diameter * count + spacing * (count - 1)
        var x = sideMargin + (available - totalWidth) / 2
        let barHeight: CGFloat = diameter + (landscape ? 10 : 16)
        topBar.frame = CGRect(x: 0, y: safeTop, width: width, height: barHeight)
        for button in topButtons {
            button.frame = CGRect(x: x, y: (barHeight - diameter) / 2,
                                  width: diameter, height: diameter)
            button.layer.cornerRadius = diameter / 2
            x += diameter + spacing
        }

        // 底部：胶囊宽度与上排按钮总跨度一致，左右端点对齐、整体居中。
        let pillHeight: CGFloat = landscape ? 56 : 64
        let barWidth = totalWidth
        let barBottomGap: CGFloat = landscape ? 8 : 12
        bottomBar.frame = CGRect(x: (width - barWidth) / 2,
                                 y: height - safeBottom - pillHeight - barBottomGap,
                                 width: barWidth,
                                 height: pillHeight)
        bottomBar.layer.cornerRadius = pillHeight / 2

        let reloadSize: CGFloat = landscape ? 30 : 34
        let playSize: CGFloat = landscape ? 34 : 38
        let iconSize: CGFloat = 13
        let speakerSize: CGFloat = 24
        let sliderHeight: CGFloat = 30
        let edgeInset: CGFloat = landscape ? 10 : 12

        reloadButton.frame = CGRect(x: edgeInset, y: (pillHeight - reloadSize) / 2,
                                    width: reloadSize, height: reloadSize)
        reloadButton.layer.cornerRadius = reloadSize / 2

        playButton.frame = CGRect(x: reloadButton.frame.maxX + 7, y: (pillHeight - playSize) / 2,
                                  width: playSize, height: playSize)
        playButton.layer.cornerRadius = playSize / 2

        let fixedWidth = edgeInset + reloadSize + 7 + playSize + 9 + iconSize + 3
            + 6 + speakerSize + 3 + edgeInset
        let sliderWidth = max(44, (barWidth - fixedWidth) / 2)

        brightnessIcon.frame = CGRect(x: playButton.frame.maxX + 9,
                                      y: (pillHeight - iconSize) / 2,
                                      width: iconSize, height: iconSize)
        brightnessSlider.frame = CGRect(x: brightnessIcon.frame.maxX + 3,
                                        y: (pillHeight - sliderHeight) / 2,
                                        width: sliderWidth,
                                        height: sliderHeight)
        speakerButton.frame = CGRect(x: brightnessSlider.frame.maxX + 6,
                                     y: (pillHeight - speakerSize) / 2,
                                     width: speakerSize, height: speakerSize)
        volumeSlider.frame = CGRect(x: speakerButton.frame.maxX + 3,
                                    y: (pillHeight - sliderHeight) / 2,
                                    width: max(44, barWidth - edgeInset - speakerButton.frame.maxX - 3),
                                    height: sliderHeight)

        statusLabel.frame = CGRect(x: 24, y: height / 2 - 20, width: width - 48, height: 40)

        // 中央播放键固定在画面正中，直径 68。
        let centerSize: CGFloat = 68
        centerPlayButton.frame = CGRect(x: (width - centerSize) / 2,
                                        y: (height - centerSize) / 2,
                                        width: centerSize, height: centerSize)
        centerPlayButton.layer.cornerRadius = centerSize / 2

        errorOverlay.frame = view.bounds
        let cardWidth = min(width - 56, 340)
        let cardHeight: CGFloat = 286
        errorCard.frame = CGRect(x: (width - cardWidth) / 2,
                                 y: (height - cardHeight) / 2,
                                 width: cardWidth,
                                 height: cardHeight)
        let inner = cardWidth - 48
        errorTitleLabel.frame = CGRect(x: 24, y: 34, width: inner, height: 26)
        errorBodyLabel.frame = CGRect(x: 24, y: 70, width: inner, height: 96)
        errorRetryButton.frame = CGRect(x: 24, y: 186, width: inner, height: 46)
        errorBackButton.frame = CGRect(x: 24, y: 238, width: inner, height: 34)

        infoOverlay.frame = view.bounds
    }

    // MARK: - WKWebView 载入

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 若脚本因故未发出 ready 事件，这里做一次兜底。
        // JS 侧等待 Ruffle 注入最多约 4s，兜底必须晚于该窗口，否则会抢跑。
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, !self.didReceiveReady else { return }
            self.didReceiveReady = true
            self.loadSWF()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showErrorOverlay(reason: error.localizedDescription)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else { return }
        let payload = body["payload"]
        DispatchQueue.main.async { [weak self] in
            self?.handle(event: event, payload: payload)
        }
    }

    private func handle(event: String, payload: Any?) {
        switch event {
        case "ready":
            guard !didReceiveReady else { return }
            didReceiveReady = true
            loadSWF()

        case "loaded":
            statusLabel.isHidden = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.captureCover()
            }

        case "metadata":
            if let dictionary = payload as? [String: Any] { metadata = dictionary }

        case "state":
            if let dictionary = payload as? [String: Any],
               let suspended = dictionary["suspended"] as? Bool {
                // 只同步播放图标（底部键 + 中央键），不改变控件显隐。
                // Ruffle 会在 SWF 内部暂停/音频上下文切换时派发 play/pause，
                // 若据此 showChrome，游戏运行途中按钮会「自己冒出来」。
                // 显隐只由：进入页面、显式点击控件、点画面唤回、定时淡出 决定。
                let changed = isPlaying != !suspended
                isPlaying = !suspended
                updatePlayButton()
                if isPlaying && changed && chromeVisible {
                    scheduleAutoHide()
                }
            }

        case "panic":
            let reason = (payload as? String) ?? "renderer panic"
            showErrorOverlay(reason: reason)

        case "error":
            let reason = (payload as? String) ?? "unknown"
            if reason == "ruffle-missing" {
                showErrorOverlay(reason: reason)
                return
            }
            if !didRetryWithData, let data = try? Data(contentsOf: LibraryStore.shared.fileURL(for: item)),
               data.count < 30_000_000 {
                didRetryWithData = true
                callJS("SWF.loadData(\(jsStringLiteral(data.base64EncodedString())), \(jsStringLiteral(item.name)))")
            } else {
                showErrorOverlay(reason: reason)
            }

        default:
            break
        }
    }

    private func loadSWF() {
        let url = PlayerURL.swfURLString(for: item.fileName)
        callJS("SWF.load(\(jsStringLiteral(url)))")
    }

    private func callJS(_ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                NSLog("[SWFPlayer] JS error: %@", error.localizedDescription)
            }
        }
    }

    private func showErrorOverlay(reason: String) {
        NSLog("[SWFPlayer] playback failed: %@", reason)
        autoHideWorkItem?.cancel()
        showChrome(animated: false)
        statusLabel.isHidden = true
        errorTitleLabel.text = L("player.loadFailedTitle")
        errorBodyLabel.text = L("player.runtimeHint")
        errorOverlay.isHidden = false
        UIView.animate(withDuration: 0.2) { self.errorOverlay.alpha = 1 }
    }

    private func hideErrorOverlay() {
        UIView.animate(withDuration: 0.18, animations: {
            self.errorOverlay.alpha = 0
        }, completion: { _ in
            self.errorOverlay.isHidden = true
        })
    }

    // MARK: - 顶部按钮动作

    @objc private func goBack() {
        if let navigationController = navigationController,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    /// 横竖屏切换：保持在播放页，只旋转界面方向。
    @objc private func toggleOrientation() {
        keepChromeAlive()
        let isLandscape = view.bounds.width > view.bounds.height
        let mask: UIInterfaceOrientationMask = isLandscape ? .portrait : .landscapeRight
        OrientationManager.allowLandscape = true

        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        } else {
            let target: UIInterfaceOrientation = isLandscape ? .portrait : .landscapeRight
            UIDevice.current.setValue(target.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.view.setNeedsLayout()
        }
    }

    @objc private func takeScreenshot() {
        keepChromeAlive()
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self = self else { return }
            guard let image = image else {
                self.showToast(L("player.snapshotFailed"))
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, self,
                                           #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
    }

    @objc private func image(_ image: UIImage,
                             didFinishSavingWithError error: NSError?,
                             contextInfo: UnsafeRawPointer?) {
        showToast(error == nil ? L("player.snapshotSaved") : L("player.snapshotFailed"))
    }

    private func captureCover() {
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self = self, let image = image else { return }
            LibraryStore.shared.setCover(for: self.item.id, image: image)
        }
    }

    /// HQ 关掉后走 Ruffle 的 low quality，牺牲画质换帧率；改动需要重新载入影片。
    @objc private func toggleHQ() {
        keepChromeAlive()
        isHQ.toggle()
        callJS("SWF.setQuality(\(jsStringLiteral(isHQ ? "high" : "low")))")
        updateOptionIndicators()
        showToast(isHQ ? L("player.qualityOn") : L("player.qualityOff"))
    }

    /// 平铺：letterbox 关闭后画面拉伸铺满，不留黑边。
    @objc private func toggleStretch() {
        keepChromeAlive()
        isStretched.toggle()
        callJS("SWF.setLetterbox(\(isStretched ? "false" : "true"))")
        updateOptionIndicators()
        showToast(isStretched ? L("player.stretchOn") : L("player.stretchOff"))
    }

    @objc private func chooseTextScale() {
        keepChromeAlive()
        let sheet = UIAlertController(title: L("player.textSize"), message: nil, preferredStyle: .actionSheet)
        for scale in TextScale.allCases {
            let mark = scale == PlaybackPreferences.textScale ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: mark + L(scale.titleKey), style: .default) { [weak self] _ in
                PlaybackPreferences.textScale = scale
                self?.applyTextScale()
                self?.showToast(L("player.textApplied", L(scale.titleKey)))
            })
        }
        sheet.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = fontButton
            popover.sourceRect = fontButton.bounds
        }
        present(sheet, animated: true)
    }

    // MARK: - 底部按钮动作

    @objc private func reloadMovie() {
        restart()
    }

    @objc private func togglePlay() {
        keepChromeAlive()
        isPlaying.toggle()
        callJS(isPlaying ? "SWF.play()" : "SWF.pause()")
        updatePlayButton()
        // 暂停时控件常驻，方便继续操作；播放时重新开始倒计时。
        if isPlaying {
            scheduleAutoHide()
        } else {
            autoHideWorkItem?.cancel()
        }
    }

    /// 中央播放键：与底部播放键共用同一套状态与 JS 调用。
    @objc private func centerPlayTapped() {
        guard !isPlaying else { return }
        togglePlay()
    }

    @objc private func restart() {
        keepChromeAlive()
        isPlaying = true
        updatePlayButton()
        hideErrorOverlay()
        statusLabel.text = L("player.loading")
        statusLabel.isHidden = false
        callJS("SWF.restart()")
    }

    @objc private func retryPlayback() {
        didRetryWithData = false
        restart()
    }

    @objc private func brightnessChanged(_ sender: UISlider) {
        keepChromeAlive()
        currentScreen.brightness = CGFloat(sender.value)
    }

    /// 喇叭按钮仍是静音开关；音量大小由下排的滑块直接调节。
    @objc private func toggleMute() {
        keepChromeAlive()
        isMuted.toggle()
        if !isMuted && volume < 0.01 { volume = 0.8 }
        applyVolume()
    }

    /// 拖动音量滑块：自动解除静音；拖到 0 视为静音。
    @objc private func volumeChanged(_ sender: UISlider) {
        keepChromeAlive()
        volume = sender.value
        isMuted = volume < 0.01
        applyVolume()
    }

    private func applyVolume() {
        let value: Float = isMuted ? 0 : volume
        callJS(String(format: "SWF.setVolume(%.3f)", Double(value)))
        volumeSlider.setValue(isMuted ? 0 : volume, animated: true)
        updateSpeaker()
    }

    // MARK: - 详情面板

    @objc private func showInfo() {
        keepChromeAlive()
        autoHideWorkItem?.cancel()
        func value(_ key: String) -> String {
            if let number = metadata[key] as? NSNumber { return number.stringValue }
            if let string = metadata[key] as? String { return string }
            return L("player.infoUnknown")
        }

        let as3 = (metadata["isActionScript3"] as? NSNumber)?.boolValue == true
            ? L("player.infoAS3Value") : L("player.infoAS12Value")

        let lines = [
            item.name,
            L("player.infoDimensions", value("width"), value("height")),
            L("player.infoFrameRate", value("frameRate")),
            L("player.infoFrames", value("numFrames")),
            L("player.infoSwfVersion", value("swfVersion")),
            L("player.infoAS3", as3),
            L("player.infoFileSize", BuildInfo.humanReadableSize(item.byteCount))
        ]

        infoRowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for line in lines {
            let label = UILabel()
            label.text = line
            label.numberOfLines = 0
            label.textColor = UIColor.white.withAlphaComponent(0.72)
            label.font = UIFont.systemFont(ofSize: 13.5)
            infoRowsStack.addArrangedSubview(label)
        }
        applyTextScale()

        infoOverlay.isHidden = false
        UIView.animate(withDuration: 0.2) { self.infoOverlay.alpha = 1 }
    }

    @objc private func dismissInfo() {
        UIView.animate(withDuration: 0.18, animations: {
            self.infoOverlay.alpha = 0
        }, completion: { _ in
            self.infoOverlay.isHidden = true
        })
        scheduleAutoHide()
    }

    // MARK: - 提示

    private func showToast(_ message: String) {
        let scale = PlaybackPreferences.textScale.multiplier
        let label = UILabel()
        label.text = message
        label.font = UIFont.systemFont(ofSize: 13 * scale)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        let width = min(view.bounds.width - 60, 320)
        let barTop = bottomBar.frame.minY
        label.frame = CGRect(x: (view.bounds.width - width) / 2,
                             y: max(24, barTop - 60),
                             width: width, height: 44)
        view.addSubview(label)
        UIView.animate(withDuration: 0.3, delay: 1.8, options: .curveEaseInOut, animations: {
            label.alpha = 0
        }, completion: { _ in label.removeFromSuperview() })
    }
}

extension PlayerViewController: UIGestureRecognizerDelegate {
    /// 只有点到遮罩本身才关闭详情面板，点卡片内部不关闭。
    /// 显隐手势只接收上/下热区里的触摸，其余全部放行给 SWF 内容。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === infoTap {
            return touch.view === infoOverlay
        }
        if gestureRecognizer === chromeTap {
            guard infoOverlay.isHidden, errorOverlay.isHidden else { return false }
            let point = touch.location(in: view)
            guard chromeHitZones().contains(where: { $0.contains(point) }) else { return false }
            if let touched = touch.view, isChromeControlHit(touched) { return false }
            return true
        }
        return true
    }

    /// 显隐手势要能和 WebView 内部的点击/滚动手势同时识别，
    /// 否则在热区里点一下会把 SWF 游戏的那次点击一起吞掉。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
