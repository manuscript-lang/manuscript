// conform: tags=closures,diagnostics,formatter,maps,numbers,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/map_transforms_test.go:37 TestMapTransformContracts
fn allowed(values Map[String, Int]) Map[String, Float] {
	return values.map((key, value) => value.to_float())
}
// expect-exit: 0
