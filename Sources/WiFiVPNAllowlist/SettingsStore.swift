import Foundation
import VPNGuardCore

enum SettingsStore {
    private static let key = "guard-settings-v1"

    static func load(from defaults: UserDefaults = .standard) -> GuardSettings? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(GuardSettings.self, from: data)
    }

    static func save(_ settings: GuardSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
