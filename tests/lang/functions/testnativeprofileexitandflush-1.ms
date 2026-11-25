// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=pkg/build/profile_test.go:26 TestNativeProfileExitAndFlush
export fn main() Int {
	return 7
}
// expect-exit: 7
