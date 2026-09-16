import Foundation

enum PathRelativizer {

    /// Resolves `path` relative to `root`, symlink-resolving both first so callers get a
    /// consistent, comparable path shape (e.g. for use as cache/metadata dictionary keys).
    /// Returns `path` unchanged if it doesn't fall under `root`.
    static func relativePath(for path: String, relativeTo root: String) -> String {
        let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard
            resolvedRoot == "/"
                || resolvedPath == resolvedRoot
                || resolvedPath.hasPrefix(resolvedRoot + "/")
        else { return path }
        return String(resolvedPath.dropFirst(resolvedRoot.count).drop(while: { $0 == "/" }))
    }

}
