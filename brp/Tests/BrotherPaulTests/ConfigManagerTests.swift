import XCTest
@testable import BrotherPaul

final class ConfigManagerTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brpaul-test-\(UUID().uuidString)", isDirectory: true)
        setenv("BROTHERPAUL_CONFIG_DIR", tmp.path, 1)
    }

    override func tearDownWithError() throws {
        // Restore the shared singleton's in-memory config to default so this
        // suite can't pollute others that assume AppConfig.default. `config` is
        // private(set), and write(_:) is the only public way to reset it — run
        // it while the env var still points at tmp so we don't touch the real
        // user config, then remove tmp.
        try? ConfigManager.shared.write(.default)
        unsetenv("BROTHERPAUL_CONFIG_DIR")
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_env_var_override_redirects_configDirectory() {
        XCTAssertEqual(ConfigManager.shared.configDirectory.path, tmp.path)
    }

    func test_bootstrap_creates_directory_and_writes_default_config() {
        ConfigManager.shared.bootstrap()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ConfigManager.shared.configFile.path))
        XCTAssertEqual(ConfigManager.shared.config.defaultMode, AppConfig.default.defaultMode)
    }

    func test_reload_after_external_write_picks_up_changes() throws {
        ConfigManager.shared.bootstrap()
        var modified = ConfigManager.shared.config
        modified.defaultMode = "Custom"
        modified.modes = [LaunchMode(name: "Custom", apps: ["TextEdit"], urls: [])]
        try ConfigManager.shared.write(modified)

        _ = try ConfigManager.shared.reload()
        XCTAssertEqual(ConfigManager.shared.config.defaultMode, "Custom")
        XCTAssertEqual(ConfigManager.shared.config.modes.first?.name, "Custom")
    }
}
