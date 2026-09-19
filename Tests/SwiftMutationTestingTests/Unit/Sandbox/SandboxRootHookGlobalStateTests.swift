import Testing

/// Shared serialization umbrella for every suite that assigns `sandboxRootCreatedHook`.
///
/// That hook is a single process-global var `SandboxFactory` calls while creating a sandbox root,
/// so a suite that installs its own hook loses it the moment another suite installs a different
/// one. Swift Testing's `.serialized` trait only keeps a suite's own tests from overlapping each
/// other — it does not keep two independently `.serialized` top-level suites from interleaving
/// under the default parallel scheduler. Nesting every hook-assigning suite as a member of this
/// one `.serialized` parent extends that guarantee across all of them.
@Suite("Tests assigning sandboxRootCreatedHook", .serialized)
enum SandboxRootHookGlobalStateTests {}
