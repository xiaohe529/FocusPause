import Foundation

struct BlockRule: Identifiable, Codable, Equatable {
    enum BlockType: String, Codable, Equatable {
        case website
        case app
    }

    var id = UUID()
    var name: String
    var type: BlockType
    var enabled = true
}
