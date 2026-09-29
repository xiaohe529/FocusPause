import Darwin
import Foundation

/// Pure validation and hosts-file formatting rules shared by the privileged helper
/// and its unit tests. Keeping these rules here avoids coupling safety checks to
/// the XPC service or the real filesystem.
public enum HelperValidation {
    public static let hostsMarkerBegin = "# FocusPause BEGIN"
    public static let hostsMarkerEnd = "# FocusPause END"

    /// Network service names passed to `networksetup`. Reject control characters and
    /// leading dashes so the value can never be mistaken for an option.
    public static func serviceNameIsValid(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 256
            && !value.hasPrefix("-")
            && !value.contains(where: {
                $0.isNewline
                    || $0.unicodeScalars.contains { $0.value == 0 || $0.properties.isDefaultIgnorableCodePoint }
            })
    }

    /// DNS server values accepted by the helper. `Empty` is `networksetup`'s token
    /// for removing custom DNS; otherwise only literal IPv4/IPv6 addresses are valid.
    public static func serverValueIsValid(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "Empty" { return true }
        guard !value.isEmpty, value == raw,
              !value.contains(where: { $0.isNewline || $0 == "\0" }) else {
            return false
        }

        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString { pointer in
            inet_pton(AF_INET, pointer, &ipv4) == 1
                || inet_pton(AF_INET6, pointer, &ipv6) == 1
        }
    }

    public static func serverListIsValid(_ servers: [String]) -> Bool {
        !servers.isEmpty && servers.allSatisfy(serverValueIsValid)
    }

    /// Builds the complete FocusPause-managed hosts content. Existing non-FocusPause
    /// lines are preserved; duplicate domains and www aliases are removed.
    public static func makeHostsContent(existing: String, domains: [String]) -> String? {
        var normalized: [String] = []
        for domain in domains {
            guard let domain = DomainNormalizer.normalize(domain) else { return nil }
            if !normalized.contains(domain) { normalized.append(domain) }
        }
        guard !normalized.isEmpty else { return nil }

        var lines = removeFocusPauseSections(from: existing)
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines.append(hostsMarkerBegin)
        for domain in normalized {
            lines.append("127.0.0.1 \(domain)")
            lines.append("127.0.0.1 www.\(domain)")
            lines.append("::1 \(domain)")
            lines.append("::1 www.\(domain)")
        }
        lines.append(hostsMarkerEnd)
        return lines.joined(separator: "\n")
    }

    /// Removes every FocusPause section, including an unterminated section, while
    /// leaving unrelated hosts entries untouched.
    public static func removeFocusPauseSections(from content: String) -> [String] {
        var result: [String] = []
        var removing = false
        var sawBegin = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !removing, trimmed == hostsMarkerBegin {
                removing = true
                sawBegin = true
                continue
            }
            if removing {
                if trimmed == hostsMarkerEnd {
                    removing = false
                }
                continue
            }
            if !sawBegin, trimmed == hostsMarkerEnd {
                // Remove a malformed trailing marker if it exists without a begin marker.
                continue
            }
            result.append(line)
        }

        // `removing` 仍为 true 表示 hosts 被截断在 BEGIN 之后、缺少 END 标记。
        // 上面的循环已经把这一整段丢弃，所以两种情况下 result 都是干净的；
        // 这里无需再分支，但保留显式说明以免后来者重新引入无意义的三元。
        while result.last?.isEmpty == true { result.removeLast() }
        return result
    }
}
