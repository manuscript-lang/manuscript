// Guard: map lookups reuse one probe, and contains, any and all fuse over strings and
// records.
type Row:
	id Int
	name String

fn main() Void:
	var counts = Map[Int, Int]()
	var rows List[Row] = []

	for i in 0..20000:
		counts[i % 997] = counts.get_or(i % 997, 0) + 1
		rows.append(Row(i, f"name{i % 311}"))

	var hits = 0
	for i in 0..20000:
		if counts.contains(i): hits += 1

	text := "the quick brown fox jumps over the lazy dog ".repeat(200)
	digits := rows.any(fn(r Row) Bool: r.name.starts_with("name3") and r.id > 19990)
	every := rows.all(fn(r Row) Bool: r.name.length() > 4)
	lower := text.chars().all(fn(c String) Bool: c != "Z")
	print(f"{hits} {digits} {every} {lower}")
