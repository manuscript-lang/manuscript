// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/snapshot_test.go:252 TestSnapshotNearestManifestIsolation
import value from "@local/value.ms"

export fn main() Int => value()
// expect-error: MS2002 4:1 unknown import alias @local; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
