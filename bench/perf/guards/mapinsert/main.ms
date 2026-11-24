// Guard: `update` and `add_default` with a borrowed key probe once and copy the key
// only for a new entry, so a map of mostly distinct keys is built without a second hash
// or a temporary key.
fn main() Void:
	var counts = Map[String, Int]()
	var seen = Map[String, Int]()
	var total = 0

	for i in 0..60000:
		key := f"record-{i % 45000}-payload"
		counts.update(key.clone(), 0, v => v + 1)
		seen.add_default(key.clone(), i)
		total += 1

	print(f"{total} {counts.length()} {seen.length()}")
