struct MutationReportLocation: Sendable, Codable {
    let start: MutationReportPosition
    let end: MutationReportPosition
}
