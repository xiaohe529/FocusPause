import Foundation

/// A user-defined encouragement phrase shown on the encouragement-cards page
/// and (optionally) as companion text on the five-senses landing page.
struct EncouragementCard: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
}