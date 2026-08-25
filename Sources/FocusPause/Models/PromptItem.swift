import Foundation

/// 一条提示，分两类：
/// - `.text`：文字提示，只在「一些提示」页以卡片形式展示，不进弹窗。
/// - `.action`：动作提示，展示在提醒弹窗里可点击，点击后跳转到「暂停一下」版块。
struct PromptItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case action
    }

    var id = UUID()
    var kind: Kind
    var text: String
}