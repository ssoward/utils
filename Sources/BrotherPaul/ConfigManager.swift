import Foundation

final class ConfigManager {
    static let shared = ConfigManager()

    private(set) var config: AppConfig = .default

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    var configDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("BrotherPaul", isDirectory: true)
    }

    var configFile: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    private init() {}

    func bootstrap() {
        do {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: configFile.path) {
                try write(.default)
            }
            try reload()
        } catch {
            NSLog("BrotherPaul: failed to bootstrap config — %@", error.localizedDescription)
        }
    }

    @discardableResult
    func reload() throws -> AppConfig {
        let data = try Data(contentsOf: configFile)
        let loaded = try decoder.decode(AppConfig.self, from: data)
        self.config = loaded
        return loaded
    }

    func write(_ config: AppConfig) throws {
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)
        self.config = config
    }
}
