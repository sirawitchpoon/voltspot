import Foundation

extension Array {
    /// Splits the array into chunks of at most `size` elements,
    /// preserving order. Last chunk may be shorter.
    ///
    /// Used at Firestore `in` query boundaries (max 30 values per
    /// query) — see `RealSessionRepository.partnerSessions`.
    func chunked(into size: Int) -> [[Element]] {
        precondition(size > 0, "chunk size must be positive")
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
