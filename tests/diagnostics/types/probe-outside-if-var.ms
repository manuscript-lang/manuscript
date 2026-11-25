// conform: tags=testing,tier-core
// conform: phase=check
fn bad(m Map[String, Int]) Void {
	x := m["a"]?
}
// expect-error: MS3000 4:10 `?` after an index is only written as `if var name = place[key]?`, where it borrows the entry in place
