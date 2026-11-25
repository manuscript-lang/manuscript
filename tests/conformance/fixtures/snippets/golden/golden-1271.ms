// conform: tags=diagnostics
// conform: phase=check
type Val {
	val Int
}

fn work(value Val) Void {
	callback := fn() Void {
		value.val += 1
	}
	callback()

	copy := value.clone()
	list := [copy]
	list.clone().append(value.clone())
}
// expect-error: MS3000 9:15 cannot change `value.val`: parameter `value` is not declared var; write `var value <Type>` in the signature
// expect-fix: 7:9-7:9 "var "
// expect-error: MS3000 8:17 cannot change `value`: parameter `value` is not declared var; write `var value <Type>` in the signature
// expect-fix: 7:9-7:9 "var "
