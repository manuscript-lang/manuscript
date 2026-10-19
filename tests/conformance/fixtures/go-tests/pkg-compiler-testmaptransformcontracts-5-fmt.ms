# conform: tags=closures,formatter,maps,numbers,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/map_transforms_test.go:37 TestMapTransformContracts
fn allowed(values: Map[String, Int]) Map[String, Float]:
    return values.map(fn(key, value): value.to_float())
