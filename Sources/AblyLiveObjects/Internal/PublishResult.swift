/// The result of a publish operation, containing serials assigned by the server.
///
/// Each serial corresponds 1:1 to the published messages. A nil serial indicates the message was discarded (e.g. by conflation).
internal struct PublishResult: Sendable {
    /// An array of serials, where each entry corresponds to one published message. Nil entries indicate conflated messages.
    internal let serials: [String?]
}
