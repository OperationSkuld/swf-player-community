import UIKit
import UniformTypeIdentifiers

// MARK: - 首页头部（品牌 / 导入卡片 / 免费说明 / 引擎卡片 / 分组标题）

final class HomeHeaderView: UIView {
    var onImport: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHelp: (() -> Void)?
    var onFeedback: (() -> Void)?
    var onEngine: (() -> Void)?

    static let preferredHeight: CGFloat = 412

    private let brandIcon = RoundedIconView(symbol: "bolt.fill", size: 44,
                                            background: Theme.red, tint: .white, corner: 13)
    private let brandLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let helpButton = Controls.chipButton(systemName: "questionmark", accessibility: "")
    private let feedbackButton = Controls.chipButton(systemName: "bubble.left", accessibility: "")
    private let settingsButton = Controls.chipButton(systemName: "gearshape", accessibility: "")

    private let importCard = GradientView()
    private let importIconBox = UIView()
    private let importIcon = UIImageView()
    private let importTitle = UILabel()
    private let importSubtitle = UILabel()
    private let importChevron = UIImageView()

    private let freeCard = UIView()
    private let freeBadge = UIView()
    private let freeStar = UIImageView()
    private let freeTitle = UILabel()
    private let freeSubtitle = UILabel()
    private let freeChevron = UIImageView()

    private let engineCard = UIView()
    private let engineIcon = RoundedIconView(symbol: "bolt.horizontal.fill", size: 44,
                                             background: Theme.red, tint: .white, corner: 13)
    private let engineTitle = UILabel()
    private let engineSubtitle = UILabel()
    private let enginePill = UILabel()

    private let recentLabel = UILabel()
    private let countBadge = UILabel()
    private let swipeHint = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        build()
        applyLocalization()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        addSubview(brandIcon)

        brandLabel.font = UIFont.systemFont(ofSize: 17, weight: .heavy)
        brandLabel.textColor = Theme.ink
        addSubview(brandLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = Theme.secondary
        addSubview(subtitleLabel)

        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        feedbackButton.addTarget(self, action: #selector(feedbackTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        [helpButton, feedbackButton, settingsButton].forEach(addSubview)

        // 主卡片
        importCard.layer.cornerRadius = 18
        importCard.layer.shadowColor = Theme.red.cgColor
        importCard.layer.shadowOpacity = 0.28
        importCard.layer.shadowOffset = CGSize(width: 0, height: 10)
        importCard.layer.shadowRadius = 18
        importCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(importTapped)))
        addSubview(importCard)

        importIconBox.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        importIconBox.layer.cornerRadius = 15
        importCard.addSubview(importIconBox)

        importIcon.image = UIImage(systemName: "folder.fill",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        importIcon.tintColor = .white
        importIcon.contentMode = .center
        importIconBox.addSubview(importIcon)

        importTitle.font = UIFont.systemFont(ofSize: 19, weight: .bold)
        importTitle.textColor = .white
        importCard.addSubview(importTitle)

        importSubtitle.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        importSubtitle.textColor = UIColor.white.withAlphaComponent(0.85)
        importSubtitle.numberOfLines = 2
        importCard.addSubview(importSubtitle)

        importChevron.image = UIImage(systemName: "chevron.right",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        importChevron.tintColor = .white
        importChevron.contentMode = .center
        importCard.addSubview(importChevron)

        // 免费说明卡片
        freeCard.backgroundColor = Theme.card
        freeCard.layer.cornerRadius = 16
        freeCard.layer.borderWidth = 1
        freeCard.layer.borderColor = Theme.cardBorder.cgColor
        Theme.applyCardShadow(freeCard, radius: 10, opacity: 0.04)
        freeCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(helpTapped)))
        addSubview(freeCard)

        freeBadge.backgroundColor = Theme.softRed
        freeBadge.layer.cornerRadius = 18
        freeCard.addSubview(freeBadge)

        freeStar.image = UIImage(systemName: "star.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        freeStar.tintColor = Theme.red
        freeStar.contentMode = .center
        freeBadge.addSubview(freeStar)

        freeTitle.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        freeTitle.textColor = Theme.ink
        freeCard.addSubview(freeTitle)

        freeSubtitle.font = UIFont.systemFont(ofSize: 12)
        freeSubtitle.textColor = Theme.red.withAlphaComponent(0.9)
        freeCard.addSubview(freeSubtitle)

        freeChevron.image = UIImage(systemName: "chevron.right",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        freeChevron.tintColor = Theme.secondary
        freeChevron.contentMode = .center
        freeCard.addSubview(freeChevron)

        // 引擎卡片
        engineCard.backgroundColor = Theme.card
        engineCard.layer.cornerRadius = 16
        Theme.applyCardShadow(engineCard, radius: 10, opacity: 0.05)
        engineCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(engineTapped)))
        addSubview(engineCard)
        engineCard.addSubview(engineIcon)

        engineTitle.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        engineTitle.textColor = Theme.ink
        engineCard.addSubview(engineTitle)

        engineSubtitle.font = UIFont.systemFont(ofSize: 12)
        engineSubtitle.textColor = Theme.secondary
        engineSubtitle.numberOfLines = 2
        engineCard.addSubview(engineSubtitle)

        enginePill.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        enginePill.textColor = .white
        enginePill.backgroundColor = Theme.red
        enginePill.textAlignment = .center
        enginePill.layer.cornerRadius = 14
        enginePill.clipsToBounds = true
        engineCard.addSubview(enginePill)

        // 最近播放
        recentLabel.font = UIFont.systemFont(ofSize: 17, weight: .heavy)
        recentLabel.textColor = Theme.ink
        addSubview(recentLabel)

        countBadge.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        countBadge.textColor = Theme.red
        countBadge.backgroundColor = Theme.softRed
        countBadge.textAlignment = .center
        countBadge.layer.cornerRadius = 9
        countBadge.clipsToBounds = true
        addSubview(countBadge)

        swipeHint.font = UIFont.systemFont(ofSize: 12)
        swipeHint.textColor = Theme.secondary
        swipeHint.textAlignment = .right
        addSubview(swipeHint)
    }

    func applyLocalization() {
        brandLabel.attributedText = NSAttributedString(
            string: "SWF PLAYER",
            attributes: [
                .kern: NSNumber(value: 0.6),
                .font: UIFont.systemFont(ofSize: 17, weight: .heavy),
                .foregroundColor: Theme.ink
            ]
        )
        subtitleLabel.text = "\(L("home.brandSub")) v\(BuildInfo.appVersion)"
        importTitle.text = L("home.importTitle")
        importSubtitle.text = L("home.importSub")
        freeTitle.text = L("home.freeTitle")
        freeSubtitle.text = L("home.freeSub")
        engineTitle.text = L("home.engineTitle")
        engineSubtitle.text = L("home.engineSub", BuildInfo.ruffleVersion)
        enginePill.text = L("home.enginePill")
        recentLabel.text = L("home.recent")
        swipeHint.text = L("home.swipeHint")
        helpButton.accessibilityLabel = L("home.help")
        feedbackButton.accessibilityLabel = L("home.feedback")
        settingsButton.accessibilityLabel = L("settings.title")
        setNeedsLayout()
    }

    func updateCount(_ count: Int) {
        countBadge.isHidden = count == 0
        countBadge.text = count > 99 ? "99+" : "\(count)"
        setNeedsLayout()
    }

    @objc private func importTapped() {
        UIView.animate(withDuration: 0.08, animations: { self.importCard.alpha = 0.85 }) { _ in
            UIView.animate(withDuration: 0.14) { self.importCard.alpha = 1.0 }
        }
        onImport?()
    }

    @objc private func settingsTapped() { onSettings?() }
    @objc private func helpTapped() { onHelp?() }
    @objc private func feedbackTapped() { onFeedback?() }
    @objc private func engineTapped() { onEngine?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let pad: CGFloat = 20

        brandIcon.frame = CGRect(x: pad, y: 18, width: 44, height: 44)
        brandLabel.frame = CGRect(x: pad + 56, y: 19, width: width - pad * 2 - 56 - 122, height: 21)
        subtitleLabel.frame = CGRect(x: pad + 56, y: 41, width: width - pad * 2 - 56 - 122, height: 16)

        let chipSize: CGFloat = 34
        var chipX = width - pad - chipSize
        for button in [settingsButton, feedbackButton, helpButton] {
            button.frame = CGRect(x: chipX, y: 23, width: chipSize, height: chipSize)
            chipX -= chipSize + 8
        }

        let cardX = pad
        let cardWidth = width - pad * 2

        importCard.frame = CGRect(x: cardX, y: 84, width: cardWidth, height: 104)
        importIconBox.frame = CGRect(x: 16, y: 24, width: 56, height: 56)
        importIcon.frame = importIconBox.bounds
        importTitle.frame = CGRect(x: 88, y: 30, width: cardWidth - 88 - 44, height: 24)
        importSubtitle.frame = CGRect(x: 88, y: 56, width: cardWidth - 88 - 44, height: 34)
        importChevron.frame = CGRect(x: cardWidth - 38, y: 42, width: 20, height: 20)

        freeCard.frame = CGRect(x: cardX, y: 202, width: cardWidth, height: 68)
        freeBadge.frame = CGRect(x: 16, y: 16, width: 36, height: 36)
        freeStar.frame = freeBadge.bounds
        freeTitle.frame = CGRect(x: 64, y: 16, width: cardWidth - 64 - 40, height: 20)
        freeSubtitle.frame = CGRect(x: 64, y: 37, width: cardWidth - 64 - 40, height: 17)
        freeChevron.frame = CGRect(x: cardWidth - 32, y: 26, width: 16, height: 16)

        engineCard.frame = CGRect(x: cardX, y: 284, width: cardWidth, height: 76)
        engineIcon.frame = CGRect(x: 16, y: 16, width: 44, height: 44)
        engineTitle.frame = CGRect(x: 72, y: 18, width: cardWidth - 72 - 78, height: 19)
        engineSubtitle.frame = CGRect(x: 72, y: 39, width: cardWidth - 72 - 78, height: 32)
        enginePill.frame = CGRect(x: cardWidth - 66, y: 24, width: 50, height: 28)

        let recentY: CGFloat = 384
        recentLabel.sizeToFit()
        recentLabel.frame = CGRect(x: pad, y: recentY, width: recentLabel.bounds.width, height: 24)
        let badgeWidth: CGFloat = max(22, countBadge.intrinsicContentSize.width + 14)
        countBadge.frame = CGRect(x: recentLabel.frame.maxX + 8, y: recentY + 3, width: badgeWidth, height: 18)

        swipeHint.sizeToFit()
        swipeHint.frame = CGRect(x: width - pad - swipeHint.bounds.width,
                                 y: recentY + 4, width: swipeHint.bounds.width, height: 18)
    }
}

// MARK: - 最近播放列表单元

final class SWFItemCell: UITableViewCell {
    static let reuseIdentifier = "SWFItemCell"

    private let container = UIView()
    private let thumbView = GradientView()
    private let thumbImage = UIImageView()
    private let boltImage = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let playIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        container.backgroundColor = Theme.card
        container.layer.cornerRadius = 16
        Theme.applyCardShadow(container, radius: 10, opacity: 0.06)
        contentView.addSubview(container)

        thumbView.layer.cornerRadius = 12
        thumbView.clipsToBounds = true
        container.addSubview(thumbView)

        boltImage.image = UIImage(systemName: "bolt.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold))
        boltImage.tintColor = .white
        boltImage.contentMode = .center
        thumbView.addSubview(boltImage)

        thumbImage.contentMode = .scaleAspectFill
        thumbImage.clipsToBounds = true
        thumbImage.layer.cornerRadius = 12
        container.addSubview(thumbImage)

        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.ink
        titleLabel.lineBreakMode = .byTruncatingMiddle
        container.addSubview(titleLabel)

        detailLabel.font = UIFont.systemFont(ofSize: 12)
        detailLabel.textColor = Theme.secondary
        container.addSubview(detailLabel)

        playIcon.image = UIImage(systemName: "play.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        playIcon.tintColor = Theme.secondary
        playIcon.contentMode = .center
        container.addSubview(playIcon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with item: SWFItem) {
        titleLabel.text = item.name
        if let date = item.lastPlayedAt {
            detailLabel.text = L("home.lastPlayed", Theme.dateFormatter.string(from: date))
        } else {
            detailLabel.text = L("home.neverPlayed")
        }

        if let coverURL = LibraryStore.shared.coverURL(for: item),
           let image = UIImage(contentsOfFile: coverURL.path) {
            thumbImage.image = image
            thumbImage.isHidden = false
            boltImage.isHidden = true
        } else {
            thumbImage.image = nil
            thumbImage.isHidden = true
            boltImage.isHidden = false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        container.frame = CGRect(x: 20, y: 4, width: width - 40, height: bounds.height - 8)
        let cardWidth = container.bounds.width
        let thumbSide: CGFloat = 52
        thumbView.frame = CGRect(x: 12, y: (container.bounds.height - thumbSide) / 2,
                                 width: thumbSide, height: thumbSide)
        boltImage.frame = thumbView.bounds
        thumbImage.frame = thumbView.frame

        let textX: CGFloat = 12 + thumbSide + 14
        titleLabel.frame = CGRect(x: textX, y: 14, width: cardWidth - textX - 40, height: 20)
        detailLabel.frame = CGRect(x: textX, y: 35, width: cardWidth - textX - 40, height: 17)
        playIcon.frame = CGRect(x: cardWidth - 34, y: (container.bounds.height - 18) / 2, width: 18, height: 18)
    }
}

// MARK: - 首页控制器

final class HomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerView = HomeHeaderView(frame: CGRect(x: 0, y: 0,
                                                          width: UIScreen.main.bounds.width,
                                                          height: HomeHeaderView.preferredHeight))
    private var languageObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationController?.setNavigationBarHidden(true, animated: false)

        tableView.backgroundColor = Theme.background
        tableView.separatorStyle = .none
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SWFItemCell.self, forCellReuseIdentifier: SWFItemCell.reuseIdentifier)
        tableView.tableHeaderView = headerView
        view.addSubview(tableView)

        headerView.onImport = { [weak self] in self?.presentImporter() }
        headerView.onSettings = { [weak self] in self?.presentSettings() }
        headerView.onHelp = { [weak self] in self?.showHelp() }
        headerView.onFeedback = { [weak self] in self?.openFeedback() }
        headerView.onEngine = { [weak self] in self?.showEngineInfo() }

        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.headerView.applyLocalization()
            self?.tableView.reloadData()
        }
    }

    deinit {
        if let observer = languageObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        headerView.updateCount(LibraryStore.shared.items.count)
        tableView.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
        let top = view.safeAreaInsets.top
        if abs(tableView.contentInset.top - top) > 0.5 {
            tableView.contentInset = UIEdgeInsets(top: top, left: 0, bottom: 28, right: 0)
            tableView.verticalScrollIndicatorInsets.top = top
        }
        if abs(headerView.bounds.width - view.bounds.width) > 0.5 {
            headerView.frame = CGRect(x: 0, y: 0,
                                      width: view.bounds.width,
                                      height: HomeHeaderView.preferredHeight)
            tableView.tableHeaderView = headerView
        }
    }

    // MARK: 导入

    private func presentImporter() {
        let swfType = UTType(filenameExtension: "swf") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [swfType, .data], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var firstItem: SWFItem?
        for url in urls {
            do {
                let item = try LibraryStore.shared.importFile(from: url)
                if firstItem == nil { firstItem = item }
            } catch {
                presentImportError(error)
                return
            }
        }
        headerView.updateCount(LibraryStore.shared.items.count)
        tableView.reloadData()
        if let item = firstItem { open(item: item) }
    }

    private func presentImportError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? L("home.importErrorGeneric")
        let alert = UIAlertController(title: L("home.importErrorTitle"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    // MARK: 导航

    func open(item: SWFItem) {
        LibraryStore.shared.touch(item.id)
        headerView.updateCount(LibraryStore.shared.items.count)
        tableView.reloadData()
        let player = PlayerViewController(item: item)
        navigationController?.pushViewController(player, animated: true)
    }

    private func presentSettings() {
        let settings = SettingsViewController(style: .insetGrouped)
        let navigation = UINavigationController(rootViewController: settings)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func showHelp() {
        let alert = UIAlertController(title: L("home.helpTitle"),
                                      message: L("home.helpBody"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func showEngineInfo() {
        let alert = UIAlertController(title: L("home.engineTitle"),
                                      message: L("home.engineDetail", BuildInfo.ruffleVersion),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func openFeedback() {
        guard let url = URL(string: "https://github.com/OperationSkuld/swf-player-community/issues") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(LibraryStore.shared.items.count, 1)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        LibraryStore.shared.items.isEmpty ? 110 : 80
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !LibraryStore.shared.items.isEmpty else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: "EmptyCell")
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineSpacing = 6
            label.attributedText = NSAttributedString(
                string: "\(L("home.emptyTitle"))\n\(L("home.emptyHint"))",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: Theme.secondary,
                    .paragraphStyle: paragraph
                ]
            )
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 36),
                label.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -36),
                label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 20)
            ])
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: SWFItemCell.reuseIdentifier, for: indexPath) as? SWFItemCell else {
            return UITableViewCell()
        }
        cell.configure(with: LibraryStore.shared.items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !LibraryStore.shared.items.isEmpty else { return }
        open(item: LibraryStore.shared.items[indexPath.row])
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !LibraryStore.shared.items.isEmpty else { return nil }
        let item = LibraryStore.shared.items[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: L("home.deleteAction")) { [weak self] _, _, completion in
            self?.confirmDelete(item)
            completion(true)
        }
        delete.backgroundColor = Theme.red

        let share = UIContextualAction(style: .normal, title: L("home.shareAction")) { [weak self] _, _, completion in
            guard let self = self else { completion(true); return }
            let url = LibraryStore.shared.fileURL(for: item)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self.present(activity, animated: true)
            completion(true)
        }
        share.backgroundColor = UIColor(hex: 0x3A3A3C)
        return UISwipeActionsConfiguration(actions: [delete, share])
    }

    private func confirmDelete(_ item: SWFItem) {
        let alert = UIAlertController(title: L("home.deleteConfirmTitle"),
                                      message: L("home.deleteConfirmMessage"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L("common.delete"), style: .destructive) { [weak self] _ in
            LibraryStore.shared.remove(item.id)
            self?.headerView.updateCount(LibraryStore.shared.items.count)
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
