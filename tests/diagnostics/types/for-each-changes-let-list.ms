// conform: tags=testing,tier-core
// conform: phase=check
fn main() Void {
	xs := [1, 2]
	xs.for_each((var n) => n += 1)
}
// expect-error: MS3060 5:5 cannot change `xs`: `xs` is an immutable binding, immutable including its contents; declare it `var xs` to change it
// expect-fix: 4:5-4:10 "var xs ="
