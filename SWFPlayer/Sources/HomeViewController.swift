import UIKit
import UniformTypeIdentifiers

// MARK: - 首页头部（品牌 / 免费标识 / 导入卡片 / 分组标题）

final class HomeHeaderView: UIView {
    var onImport: (() -> Void)?
    var onSettings: (() -> Void)?

    private let brandLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let freeBadge = UILabel()
    private let importCard = GradientView(frame: .zero)
    private let plusIcon = UIImageView()
    private let importTitle = UILabel()
    private let importSubtitle = UILabel()
    private let watermark = UILabel()
    private let recentLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        brandLabel.attributedText = NSAttributedString(
            string: "SWF PLAYER",
            attributes: [
                .kern: NSNumber(value: 3.0),
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: Theme.red
            ]
        )
        addSubview(brandLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        subtitleLabel.textColor = Theme.red.withAlphaComponent(0.85)
        addSubview(subtitleLabel)

        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        settingsButton.setImage(UIImage(systemName: "slider.horizontal.3", withConfiguration: symbol), for: .normal)
        settingsButton.tintColor = Theme.red
        settingsButton.layer.borderWidth = 1.5
        settingsButton.layer.borderColor = Theme.red.cgColor
        settingsButton.layer.cornerRadius = 20
        settingsButton.clipsToBounds = true
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        addSubview(settingsButton)

        freeBadge.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        freeBadge.textColor = Theme.red
        freeBadge.backgroundColor = Theme.softRed
        freeBadge.textAlignment = .center
        freeBadge.layer.cornerRadius = 13
        freeBadge.clipsToBounds = true
        addSubview(freeBadge)

        importCard.layer.shadowColor = Theme.red.cgColor
        importCard.layer.shadowOpacity = 0.22
        importCard.layer.shadowOffset = CGSize(width: 0, height: 8)
        importCard.layer.shadowRadius = 16
        importCard.layer.shadowPath = nil
        importCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(importTapped)))
        importCard.isUserInteractionEnabled = true
        addSubview(importCard)

        plusIcon.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .bold))
        plusIcon.tintColor = .white
        importCard.addSubview(plusIcon)

        importTitle.font = UIFont.boldSystemFont(ofSize: 16)
        importTitle.textColor = .white
        importCard.addSubview(importTitle)

        importSubtitle.font = UIFont.systemFont(ofSize: 11)
        importSubtitle.textColor = UIColor.white.withAlphaComponent(0.88)
        importCard.addSubview(importSubtitle)

        watermark.text = "7"
        watermark.font = UIFont.boldSystemFont(ofSize: 96)
        watermark.textColor = UIColor.white.withAlphaComponent(0.13)
        watermark.textAlignment = .right
        importCard.addSubview(watermark)

        recentLabel.font = UIFont.boldSystemFont(ofSize: 16)
        recentLabel.textColor = Theme.ink
        addSubview(recentLabel)

        applyLocalization()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyLocalization() {
        subtitleLabel.text = L("home.brandSub")
        freeBadge.text = "✓  " + L("home.freeBadge")
        importTitle.text = L("home.importTitle")
        importSubtitle.text = L("home.importSub")
        recentLabel.text = L("home.recent")
        settingsButton.accessibilityLabel = L("settings.title")
    }

    @objc private func importTapped() {
        UIView.animate(withDuration: 0.08, animations: { self.importCard.alpha = 0.82 }) { _ in
            UIView.animate(withDuration: 0.12) { self.importCard.alpha = 1.0 }
        }
        onImport?()
    }

    @objc private func openSettings() { onSettings?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let pad: CGFloat = 22
        settingsButton.frame = CGRect(x: width - pad - 40, y: 22, width: 40, height: 40)
        brandLabel.frame = CGRect(x: pad, y: 24, width: width - pad * 2 - 52, height: 32)
        subtitleLabel.frame = CGRect(x: pad, y: 58, width: width - pad * 2, height: 16)
        freeBadge.frame = CGRect(x: pad, y: 82, width: width - pad * 2, height: 26)

        let cardWidth = width - pad * 2
        importCard.frame = CGRect(x: pad, y: 122, width: cardWidth, height: 118)
        plusIcon.frame = CGRect(x: 18, y: 16, width: 26, height: 26)
        importTitle.frame = CGRect(x: 18, y: 50, width: cardWidth - 36, height: 23)
        importSubtitle.frame = CGRect(x: 18, y: 76, width: cardWidth - 36, height: 18)
        watermark.frame = CGRect(x: cardWidth - 92, y: 4, width: 78, height: 112)

        recentLabel.frame = CGRect(x: pad, y: 262, width: width - pad * 2, height: 22)
    }
}

// MARK: - 最近播放列表单元

final class SWFItemCell: UITableViewCell {
    static let reuseIdentifier = "SWFItemCell"

    private let container = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevron = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        container.backgroundColor = Theme.card
        container.layer.cornerRadius = 14
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.05
        container.layer.shadowOffset = CGSize(width: 0, height: 3)
        container.layer.shadowRadius = 8
        contentView.addSubview(container)

        iconView.contentMode = .scaleAspectFill
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 9
        iconView.backgroundColor = Theme.softRed
        iconView.tintColor = Theme.red
        container.addSubview(iconView)

        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Theme.ink
        titleLabel.lineBreakMode = .byTruncatingMiddle
        container.addSubview(titleLabel)

        detailLabel.font = UIFont.systemFont(ofSize: 11)
        detailLabel.textColor = Theme.secondary
        container.addSubview(detailLabel)

        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        chevron.tintColor = Theme.secondary
        chevron.contentMode = .center
        container.addSubview(chevron)
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
            iconView.image = image
        } else {
            iconView.image = UIImage(systemName: "bolt.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        container.frame = CGRect(x: 20, y: 5, width: width - 40, height: bounds.height - 10)
        let cardWidth = container.bounds.width
        iconView.frame = CGRect(x: 14, y: (container.bounds.height - 40) / 2, width: 40, height: 40)
        let textX: CGFloat = 66
        titleLabel.frame = CGRect(x: textX, y: 15, width: cardWidth - textX - 36, height: 20)
        detailLabel.frame = CGRect(x: textX, y: 37, width: cardWidth - textX - 36, height: 17)
        chevron.frame = CGRect(x: cardWidth - 30, y: (container.bounds.height - 16) / 2, width: 14, height: 16)
    }
}

// MARK: - 首页控制器

final class HomeViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerView = HomeHeaderView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 292))
    private var languageObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationController?.setNavigationBarHidden(true, animated: false)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SWFItemCell.self, forCellReuseIdentifier: SWFItemCell.reuseIdentifier)
        tableView.tableHeaderView = headerView
        tableView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(tableView)

        headerView.onImport = { [weak self] in self?.presentImporter() }
        headerView.onSettings = { [weak self] in self?.presentSettings() }

        languageObserver = NotificationCenter.default.addObserver(
            forName: .appLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.headerView.applyLocalization()
            self?.tableView.reloadData()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        tableView.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
        if abs(headerView.bounds.width - view.bounds.width) > 0.5 {
            headerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 292)
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
        tableView.reloadData()
        let player = PlayerViewController(item: item)
        navigationController?.pushViewController(player, animated: true)
    }

    private func presentSettings() {
        let settings = SettingsViewController(style: .insetGrouped)
        let navigation = UINavigationController(rootViewController: settings)
        present(navigation, animated: true)
    }

    // MARK: UITableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(LibraryStore.shared.items.count, 1)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        LibraryStore.shared.items.isEmpty ? 96 : 76
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !LibraryStore.shared.items.isEmpty else {
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "EmptyCell")
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.textLabel?.text = L("home.emptyTitle")
            cell.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            cell.textLabel?.textColor = Theme.secondary
            cell.detailTextLabel?.text = L("home.emptyHint")
            cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 11)
            cell.detailTextLabel?.textColor = Theme.secondary
            cell.detailTextLabel?.numberOfLines = 3
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
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
