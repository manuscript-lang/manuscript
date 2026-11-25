// conform: tags=diagnostics,modules,tier-core
// conform: phase=check
// conform: origin=internal/cli/project_check_test.go:52 TestProjectCheckDiscoveryAndReporting
import value from "@lib/value.ms"

fn report() Int => return value()
// expect-error: MS2002 4:1 unknown import alias @lib; this project declares none, so add one under [aliases] in ms.toml, e.g. "@lib" = "./src/lib" (use @std/... for the standard library)
