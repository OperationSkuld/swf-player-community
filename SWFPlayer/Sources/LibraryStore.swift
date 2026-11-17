import Foundation
import UIKit

struct SWFItem: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var fileName: String
    var byteCount: Int64
    var addedAt: Date
    var lastPlayedAt: Date?
    var hasCover: Bool
}

enum LibraryError: LocalizedError {
    case unsupportedType
    case invalidFile
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupportedType: return L("home.importErrorUnsupported")
        case .invalidFile: return L("home.importErrorInvalid")
        case .unreadable: return L("home.importErrorGeneric")
        }
    }
}

/// 导入的 SWF 会被复制进应用自己的文稿目录，避免依赖外部 URL 的书签失效。
/// 元数据用 JSON 持久化，纯本地，不上传任何内容。
final class LibraryStore {
    static let shared = LibraryStore()

    private let fileManager = FileManager.default
    private init() { prepare(); load() }

    private(set) var items: [SWFItem] = []

    private var rootURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("SWFLibrary", isDirectory: true)
    }

    private var coversURL: URL { rootURL.appendingPathComponent("Covers", isDirectory: true) }
    private var indexURL: URL { rootURL.appendingPathComponent("index.json") }

    /// WKWebView 自定义 scheme 需要通过 /swf/<fileName> 读取文件，因此目录必须对外可见。
    var swfDirectoryURL: URL { rootURL }

    func prepare() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: coversURL, withIntermediateDirectories: true)
    }

    func fileURL(for item: SWFItem) -> URL {
        rootURL.appendingPathComponent(item.fileName)
    }

    func coverURL(for item: SWFItem) -> URL? {
        guard item.hasCover else { return nil }
        let url = coversURL.appendingPathComponent(item.id + ".jpg")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func importFile(from source: URL) throws -> SWFItem {
        prepare()
        guard source.pathExtension.lowercased() == "swf" else { throw LibraryError.unsupportedType }

        let needsSecurityScope = source.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { source.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: source, options: .mappedIfSafe) else {
            throw LibraryError.unreadable
        }
        return try store(data: data, name: source.lastPathComponent)
    }

    /// 直接从网络下载得到的字节入库，省掉 "先存文件再导入" 的中间步骤。
    @discardableResult
    func importRemote(data: Data, fileName: String) throws -> SWFItem {
        prepare()
        var name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "remote.swf" }
        if !name.lowercased().hasSuffix(".swf") { name += ".swf" }
        return try store(data: data, name: name)
    }

    /// 校验 SWF 签名、去重、落盘并写入索引。
    @discardableResult
    private func store(data: Data, name: String) throws -> SWFItem {
        guard data.count >= 9 else { throw LibraryError.invalidFile }
        // SWF 文件头：FWS（未压缩）/ CWS（zlib）/ ZWS（LZMA）
        let signature = String(decoding: data.prefix(3), as: UTF8.self)
        guard ["FWS", "CWS", "ZWS"].contains(signature) else { throw LibraryError.invalidFile }

        // 同名同大小重复导入时只更新索引，不留下垃圾副本。
        if let existing = items.first(where: { $0.name == name && $0.byteCount == Int64(data.count) }) {
            touch(existing.id)
            return existing
        }

        let id = UUID().uuidString
        let storedName = id + ".swf"
        let destination = rootURL.appendingPathComponent(storedName)
        try data.write(to: destination, options: .atomic)

        let item = SWFItem(
            id: id,
            name: name,
            fileName: storedName,
            byteCount: Int64(data.count),
            addedAt: Date(),
            lastPlayedAt: nil,
            hasCover: false
        )
        items.insert(item, at: 0)
        save()
        return item
    }

    func item(id: String) -> SWFItem? { items.first { $0.id == id } }

    func touch(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].lastPlayedAt = Date()
        moveToFront(index)
        save()
    }

    func setCover(for id: String, image: UIImage) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let jpeg = image.jpegData(compressionQuality: 0.72) else { return }
        try? jpeg.write(to: coversURL.appendingPathComponent(id + ".jpg"), options: .atomic)
        items[index].hasCover = true
        save()
    }

    func remove(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        try? fileManager.removeItem(at: fileURL(for: item))
        try? fileManager.removeItem(at: coversURL.appendingPathComponent(id + ".jpg"))
        items.remove(at: index)
        save()
    }

    func clearAll() {
        for item in items { try? fileManager.removeItem(at: fileURL(for: item)) }
        try? fileManager.removeItem(at: coversURL)
        items.removeAll()
        prepare()
        save()
    }

    private func moveToFront(_ index: Int) {
        let item = items.remove(at: index)
        items.insert(item, at: 0)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SWFItem].self, from: data) else { return }
        items = decoded.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
    }
}
