// conform: tags=closures,diagnostics,maps,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/map_transforms_test.go:18 TestMapTransformContracts
fn wrong(values Map[String, Int]) Void {
	found := values.find_last((k, v) => v)
}
// expect-error: MS3001 5:41 expected Bool, found Int (in the return value)
