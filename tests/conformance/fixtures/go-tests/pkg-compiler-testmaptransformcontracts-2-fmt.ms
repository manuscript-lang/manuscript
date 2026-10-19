# conform: tags=closures,formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/map_transforms_test.go:14 TestMapTransformContracts
fn wrong[W](values: Map[String, Int], transform: fn(key: String, value: Int) W) Unit:
    let mapped = values.map_keys(transform)
