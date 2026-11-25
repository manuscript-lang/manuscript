// conform: tags=diagnostics
// conform: phase=check
fn f(counts Map[String, Int], names List[String], found Int?) Void {
	match found {
		n => {
			counts.add(key: "a", value: n)
		}
		null => {
			names.append("x")
		}
	}
}
// expect-error: MS3000 6:13 cannot change `counts`: parameter `counts` is not declared var; write `var counts <Type>` in the signature
// expect-fix: 3:6-3:6 "var "
// expect-error: MS3000 9:13 cannot change `names`: parameter `names` is not declared var; write `var names <Type>` in the signature
// expect-fix: 3:31-3:31 "var "
