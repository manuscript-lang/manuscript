# conform: tags=diagnostics,modules,stdlib-toml,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/standard_lazy_test.go:33 TestBundledSourceModulesCheckOnFirstImport
import TomlValue from "@std/data/toml.ms"

fn one() Int:
    return 1
