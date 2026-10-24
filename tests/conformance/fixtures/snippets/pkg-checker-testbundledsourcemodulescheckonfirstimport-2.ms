# conform: tags=diagnostics,modules,stdlib-toml,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/standard_lazy_test.go:33 TestBundledSourceModulesCheckOnFirstImport
from "@std/toml.ms" import TomlValue

def one() -> Int:
    return 1
