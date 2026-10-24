# conform: tags=formatter,modules,parser,stdlib-toml,stdlib-yaml,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/standard_lazy_test.go:46 TestBundledSourceModulesCheckOnceConcurrently
from "@std/toml.ms" import TomlValue
from "@std/yaml.ms" import YamlValue

def one() -> Int:
    return 1
