// conform: tags=closures,diagnostics,maps,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/map_transforms_test.go:14 TestMapTransformContracts
fn wrong[W](values Map[String, Int], transform fn(String, Int) W) Void {
	mapped := values.map_keys(transform)
}
// expect-error: MS3021 5:22 W does not satisfy Hashable; pass a type that already implements it
