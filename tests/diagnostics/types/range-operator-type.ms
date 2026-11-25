// conform: tags=control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=range operator a..b
export fn main() Int {
	for i in 0.."x" {
		return i
	}
	return 0
}
// expect-error: MS3001 5:17 expected Int, found String (in argument 'end' of ..)
