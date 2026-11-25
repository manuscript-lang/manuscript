// conform: tags=numbers,tier-core
// conform: phase=run
// A value exactly between two shortest decimals prints the one with an even last digit.
export fn main() Int {
	wide := 29501041598734.3125
	narrow Float32 := 3423159.25
	print(f"{wide} {narrow} {1313322917213848.25}")
	return 0
}
// expect-exit: 0
// expect-stdout: 29501041598734.312 3423159.2 1313322917213848.2
