# conform: tags=formatter,modules,parser,stdlib-toml,stdlib-yaml,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/standard_lazy_test.go:46 TestBundledSourceModulesCheckOnceConcurrently
import TomlValue from "@std/toml.ms"
import YamlValue from "@std/yaml.ms"

fn one() Int:
    return 1
