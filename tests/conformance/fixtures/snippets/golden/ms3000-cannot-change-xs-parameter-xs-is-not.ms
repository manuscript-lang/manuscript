// conform: tags=diagnostics
// conform: phase=check
fn f(xs List[Int], o Int?) Void {
	var n = 0

	match o {
		v => {
			n = v
			xs.set(index: 0, value: 5)
		}
		null => {
			n = 2
		}
	}

	xs.append(n)
}
// expect-error: MS3000 9:13 cannot change `xs`: parameter `xs` is not declared var; write `var xs <Type>` in the signature
// expect-fix: 3:6-3:6 "var "
// expect-error: MS3000 16:5 cannot change `xs`: parameter `xs` is not declared var; write `var xs <Type>` in the signature
// expect-fix: 3:6-3:6 "var "
