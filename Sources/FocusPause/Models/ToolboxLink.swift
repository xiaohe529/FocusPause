import Foundation

/// 暂停工具箱里的一条入口：网页外链 或 本机应用。
struct ToolboxLink: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case link   // 网页外链（默认）
        case app    // 本机应用（url 存 .app 绝对路径）
    }
    var id = UUID()
    var title: String
    /// link 类型存网址；app 类型存应用 bundle 绝对路径。
    var url: String
    var kind: Kind = .link
}

/// 暂停工具箱里的一个分组：可自命名，内含若干链接。
struct ToolboxGroup: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var links: [ToolboxLink]
}