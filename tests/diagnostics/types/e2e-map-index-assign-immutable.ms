// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	scores := {"a": 1}
	scores["b"] = 2
	return scores["a"]
}
// expect-error: MS3060 5:5 cannot change `scores`: `scores` is an immutable binding, immutable including its contents; declare it `var scores` to change it
// expect-fix: 4:5-4:14 "var scores ="
