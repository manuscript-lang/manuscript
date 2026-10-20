# conform: tags=closures,formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/map_transforms_test.go:12 TestMapTransformContracts
fn wrong(values: Map[String, Int]) Unit:
    let mapped = values.map_keys(fn(k, v): v.to_float())
