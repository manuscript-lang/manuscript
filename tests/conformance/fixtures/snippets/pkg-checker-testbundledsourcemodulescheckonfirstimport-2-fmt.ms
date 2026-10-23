# conform: tags=formatter,modules,parser,stdlib-toml,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/standard_lazy_test.go:33 TestBundledSourceModulesCheckOnFirstImport
import TomlValue from "@std/toml.ms"

fn one() Int:
    return 1
