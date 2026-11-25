// conform: tags=diagnostics
// conform: phase=check
fn use(values List[Int], entries Map[String, Int], unique Set[Int]) Void {
	entries.add("a", 1)
}
// expect-error: MS3000 4:5 cannot change `entries`: parameter `entries` is not declared var; write `var entries <Type>` in the signature
// expect-fix: 3:26-3:26 "var "
