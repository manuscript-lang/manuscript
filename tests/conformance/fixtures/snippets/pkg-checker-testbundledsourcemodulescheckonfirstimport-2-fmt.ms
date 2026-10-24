# conform: tags=formatter,modules,parser,stdlib-toml,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/standard_lazy_test.go:33 TestBundledSourceModulesCheckOnFirstImport
from "@std/toml.ms" import TomlValue

def one() -> Int:
    return 1
