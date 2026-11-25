// conform: tags=diagnostics,formatter,interfaces,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lower/int_bounds_test.go:163 BenchmarkClosedMapProofScaling
interface Tag {
	fn tag() Int
}
// expect-exit: 0
