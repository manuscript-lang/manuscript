// conform: tags=diagnostics,tier-core
// conform: phase=check
export fn main() Int {
	print(min(1, 2))
	return 0
}
// expect-error: MS2001 4:11 unknown binding min; add: import min from "@std/math/math.ms"
// expect-fix: 1:1-1:1 "import min from \"@std/math/math.ms\"\n"
