struct MutationReportFile: Sendable, Codable {
    let language: String
    let source: String
    let mutants: [MutationReportMutant]
}
