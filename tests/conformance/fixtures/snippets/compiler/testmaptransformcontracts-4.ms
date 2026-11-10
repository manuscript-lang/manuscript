// conform: tags=closures,diagnostics,maps,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/map_transforms_test.go:18 TestMapTransformContracts
fn wrong(values: Map[String, Int]) Unit:
    found := values.find_last(fn k, v: v)
