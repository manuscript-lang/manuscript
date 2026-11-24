// conform: tags=closures,diagnostics,maps,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/map_transforms_test.go:12 TestMapTransformContracts
fn wrong(values Map[String, Int]) Void:
    mapped := values.map_keys((k, v) => v.to_float())
