import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit

// MARK: - Official Scopegram Badges (Managed strictly via GitHub badges.json)

public enum ScopegramBadgeType: String, Codable, Equatable {
    case developer = "developer"
    case official = "official"
    case supporter = "supporter"
    
    public var title: String {
        switch self {
        case .developer:
            return "Scopegram Developer"
        case .official:
            return "Official Scopegram Channel"
        case .supporter:
            return "Scopegram Supporter"
        }
    }
    
    public var description: String {
        switch self {
        case .developer:
            return "Этот аккаунт является разработчиком клиента Scopegram."
        case .official:
            return "Официальный подтверждённый канал экосистемы Scopegram."
        case .supporter:
            return "Этот пользователь поддержал развитие Scopegram."
        }
    }
}

public final class ScopegramBadges {
    public static let shared = ScopegramBadges()
    
    private let lock = NSLock()
    
    // Remote & bundled IDs (zero hardcode, strictly from JSON)
    private var developerIds: Set<Int64> = []
    private var officialIds: Set<Int64> = []
    private var supporterIds: Set<Int64> = []
    
    private init() {
        self.loadInitialBadges()
        self.syncWithRemote()
    }
    
    private func getCacheFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("Scopegram", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("badges_cache.json")
    }
    
    private func loadInitialBadges() {
        // 1. Try bundled badges.json inside .app
        if let bundlePath = Bundle.main.path(forResource: "badges", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            self.parseJSON(json)
        }
        
        // 2. Try cached remote JSON
        if let cacheUrl = getCacheFileURL(),
           let data = try? Data(contentsOf: cacheUrl),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            self.parseJSON(json)
        }
    }
    
    public func badge(for peer: Peer) -> ScopegramBadgeType? {
        return badge(for: peer.id)
    }
    
    public func badge(for peerId: PeerId) -> ScopegramBadgeType? {
        lock.lock()
        defer { lock.unlock() }
        
        let id = abs(peerId.id._internalGetInt64Value())
        if peerId.namespace == Namespaces.Peer.CloudUser, developerIds.contains(id) {
            return .developer
        }
        if peerId.namespace == Namespaces.Peer.CloudChannel, officialIds.contains(id) {
            return .official
        }
        if peerId.namespace == Namespaces.Peer.CloudUser, supporterIds.contains(id) {
            return .supporter
        }
        return nil
    }
    
    public func syncWithRemote() {
        guard let url = URL(string: "https://raw.githubusercontent.com/lonestill/scopeGram/master/badges.json") else { return }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.parseJSON(json)
                    if let cacheUrl = self.getCacheFileURL() {
                        try? data.write(to: cacheUrl, options: .atomic)
                    }
                }
            } catch {
                // Ignore parse errors
            }
        }.resume()
    }
    
    private func parseJSON(_ json: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        
        var newDevIds = Set<Int64>()
        if let devs = json["developers"] as? [Any] {
            for item in devs {
                if let num = item as? NSNumber {
                    newDevIds.insert(abs(num.int64Value))
                } else if let s = item as? String, let id = Int64(s) {
                    newDevIds.insert(abs(id))
                }
            }
        }
        
        var newOfficialIds = Set<Int64>()
        if let channels = json["official_channels"] as? [Any] {
            for item in channels {
                if let num = item as? NSNumber {
                    newOfficialIds.insert(abs(num.int64Value))
                } else if let s = item as? String, let id = Int64(s) {
                    newOfficialIds.insert(abs(id))
                }
            }
        }
        
        var newSupIds = Set<Int64>()
        if let supporters = json["supporters"] as? [Any] {
            for item in supporters {
                if let num = item as? NSNumber {
                    newSupIds.insert(abs(num.int64Value))
                } else if let s = item as? String, let id = Int64(s) {
                    newSupIds.insert(abs(id))
                }
            }
        }
        
        self.developerIds = newDevIds
        self.officialIds = newOfficialIds
        self.supporterIds = newSupIds
    }
}

// MARK: - Local Telegram Badges (Verified / Scam / Fake) Configured in Settings

public enum LocalTelegramBadgeKind: String, Codable, CaseIterable {
    case verified = "verified"
    case fake = "fake"
    case scam = "scam"
    
    public var title: String {
        switch self {
        case .verified:
            return "Verified (Галочка)"
        case .fake:
            return "Fake (Метка Fake)"
        case .scam:
            return "Scam (Метка Scam)"
        }
    }
}

public final class LocalTelegramBadges {
    public static let shared = LocalTelegramBadges()

    private struct StoredBadge: Codable {
        let peerId: PeerId
        let kind: LocalTelegramBadgeKind
    }

    private let storageKey = "scopegram.local_badges.v2"
    private let verifiedKey = "scopegram.local_badges.verified"
    private let scamKey = "scopegram.local_badges.scam"
    private let fakeKey = "scopegram.local_badges.fake"

    private var badges: [PeerId: LocalTelegramBadgeKind] = [:]
    private let lock = NSLock()

    private init() {
        load()
    }

    private func load() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: storageKey), let stored = try? JSONDecoder().decode([StoredBadge].self, from: data) {
            badges = Dictionary(uniqueKeysWithValues: stored.map { ($0.peerId, $0.kind) })
            return
        }

        migrateLegacy(ud.stringArray(forKey: verifiedKey), kind: .verified)
        migrateLegacy(ud.stringArray(forKey: scamKey), kind: .scam)
        migrateLegacy(ud.stringArray(forKey: fakeKey), kind: .fake)
        save()
    }

    private func migrateLegacy(_ values: [String]?, kind: LocalTelegramBadgeKind) {
        for id in values?.compactMap(Int64.init) ?? [] {
            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(abs(id)))
            badges[peerId] = kind
        }
    }

    private func save() {
        let stored = badges.map { StoredBadge(peerId: $0.key, kind: $0.value) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func badge(for peerId: PeerId) -> LocalTelegramBadgeKind? {
        lock.lock()
        defer { lock.unlock() }
        return badges[peerId]
    }

    public func assign(peerId: PeerId, kind: LocalTelegramBadgeKind) {
        lock.lock()
        defer { lock.unlock() }
        badges[peerId] = kind
        save()
    }

    public func remove(peerId: PeerId) {
        lock.lock()
        defer { lock.unlock() }
        badges.removeValue(forKey: peerId)
        save()
    }

    public func allBadges() -> [(peerId: PeerId, kind: LocalTelegramBadgeKind)] {
        lock.lock()
        defer { lock.unlock() }
        return badges.map { ($0.key, $0.value) }
    }
}
