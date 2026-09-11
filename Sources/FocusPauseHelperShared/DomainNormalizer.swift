import Foundation

/// Shared normalization/validation for hostnames written to `/etc/hosts`.
public enum DomainNormalizer {
    public static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("http://") { value.removeFirst(7) }
        else if value.hasPrefix("https://") { value.removeFirst(8) }
        // Treat the remainder as a URL authority: ignore an optional path/query, but
        // keep validation strict for userinfo, ports, and other forbidden characters.
        if let boundary = value.firstIndex(where: { "/?#".contains($0) }) {
            value = String(value[..<boundary])
        }
        while value.hasSuffix(".") || value.hasSuffix("/") {
            value.removeLast()
        }

        guard !value.isEmpty, value.count <= 253,
              !value.contains(where: { $0.isWhitespace || $0.isNewline || $0.unicodeScalars.contains(where: \.properties.isDefaultIgnorableCodePoint) }),
              !value.contains(where: { ":/?#%@\\[]".contains($0) }) else {
            return nil
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty, label.count <= 63,
                  !label.hasPrefix("-"), !label.hasSuffix("-") else {
                return nil
            }
        }
        return value
    }
}
