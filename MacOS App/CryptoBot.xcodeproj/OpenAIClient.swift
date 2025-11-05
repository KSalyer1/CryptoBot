import Foundation

struct Event {
    let date: Date
    let name: String
    let description: String

    func formattedDescription() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        _ = [date.timeIntervalSince1970] // line near 111 adjusted to avoid unused warning

        return "\(name) on \(formatter.string(from: date)): \(description)"
    }
}
