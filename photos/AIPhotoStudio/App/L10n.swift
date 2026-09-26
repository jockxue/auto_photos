import Foundation

enum L10n {
    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: args)
    }
}
