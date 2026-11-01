# conform: tags=diagnostics,modules,stdlib-toml,stdlib-yaml,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/standard_lazy_test.go:46 TestBundledSourceModulesCheckOnceConcurrently
import TomlValue from "@std/data/toml.ms"
import YamlValue from "@std/data/yaml.ms"

fn one() Int:
    return 1
