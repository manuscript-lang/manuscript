# conform: tags=formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/map_transforms_test.go:16 TestMapTransformContracts
fn transform(value: Int, key: String) Int: value
fn wrong(values: Map[String, Int]) Map[String, Int]: values.map(transform)
