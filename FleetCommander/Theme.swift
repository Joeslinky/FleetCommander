import UIKit
import Darwin

enum AppTheme {
    static let accent = UIColor(red: 0.12, green: 0.73, blue: 0.62, alpha: 1)
    static let accentPressed = UIColor(red: 0.08, green: 0.58, blue: 0.50, alpha: 1)
    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 14

    static func apply() {
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = accent
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
        configuration.baseForegroundColor = AppTheme.accent
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        let button = UIButton(configuration: configuration)
        return button
    }
}
