import UIKit
import Darwin

enum AppTheme {
    /// Pond `--main-bg`
    static let background = UIColor(red: 0.043, green: 0.106, blue: 0.043, alpha: 1) // #0b1b0b
    /// Pond `--secondary-bg` / sidebar
    static let surface = UIColor(red: 0.149, green: 0.251, blue: 0.149, alpha: 1) // #264026
    /// Pond `--input-bg`
    static let input = UIColor(red: 0.184, green: 0.329, blue: 0.196, alpha: 1) // #2f5432
    /// Pond `--main-fg`
    static let accent = UIColor(red: 0.090, green: 0.525, blue: 0.263, alpha: 1) // #178643
    /// Pond `--success-text`
    static let accentBright = UIColor(red: 0.200, green: 0.820, blue: 0.227, alpha: 1) // #33d13a
    static let text = UIColor.white
    static let textMuted = UIColor(red: 0.627, green: 0.627, blue: 0.627, alpha: 1)
    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 14

    static func apply() {
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = accentBright
    }
}

enum ConnectionStore {
    private static let addressKey = "SavedIPAddress"
    private static let portKey = "SavedPort"

    static var savedAddress: String? {
        UserDefaults.standard.string(forKey: addressKey)
    }

    static var savedPort: Int? {
        guard UserDefaults.standard.object(forKey: portKey) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: portKey)
    }

    static var savedConnection: (address: String, port: Int)? {
        guard let address = savedAddress, let port = savedPort else { return nil }
        return (address, port)
    }

    static func save(address: String, port: Int) {
        UserDefaults.standard.set(address, forKey: addressKey)
        UserDefaults.standard.set(port, forKey: portKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: addressKey)
        UserDefaults.standard.removeObject(forKey: portKey)
    }
}

enum AddressValidator {
    static let defaultPort = 8082

    static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ raw: String) -> Bool {
        let value = sanitized(raw)
        return isIPv4(value) || isHostname(value)
    }

    static func port(from raw: String?) -> Int? {
        let text = sanitized(raw ?? "")
        if text.isEmpty { return defaultPort }
        guard let port = Int(text), (1...65535).contains(port) else { return nil }
        return port
    }

    private static func isIPv4(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private static func isHostname(_ value: String) -> Bool {
        if value.caseInsensitiveCompare("localhost") == .orderedSame { return true }
        let hostnameRegex = #"^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"#
        return NSPredicate(format: "SELF MATCHES %@", hostnameRegex).evaluate(with: value)
    }

    static func ipSortKey(_ ip: String) -> (Int, Int, Int, Int) {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return (0, 0, 0, 0) }
        return (parts[0], parts[1], parts[2], parts[3])
    }
}

extension UIButton {
    static func appFilled(title: String, color: UIColor = AppTheme.accent) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .fixed
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.layer.cornerRadius = AppTheme.controlCornerRadius
        button.clipsToBounds = true
        return button
    }

    static func appPlain(title: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = AppTheme.accentBright
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        let button = UIButton(configuration: configuration)
        return button
    }
}
