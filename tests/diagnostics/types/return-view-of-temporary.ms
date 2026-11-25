// conform: tags=testing,tier-core
// conform: phase=check
// `slice` answers a new String, so `trim` of it borrows a temporary that is gone when the
// function returns; returning that view would hand the caller freed memory. Copy it with
// `.clone()`.
fn header(source String) String {
	for line in source.lines() {
		if line.starts_with("// removed") {
			return line.slice(3, line.length()).trim()
		}
	}
	return ""
}

export fn main() Int {
	return header("// removed: a long long long long value here").length()
}
