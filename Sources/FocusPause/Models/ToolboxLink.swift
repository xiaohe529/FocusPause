import Foundation

/// 暂停工具箱里的一条外链：标题 + 地址。
struct ToolboxLink: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String
}

/// 暂停工具箱里的一个分组：可自命名，内含若干链接。
struct ToolboxGroup: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var links: [ToolboxLink]
}