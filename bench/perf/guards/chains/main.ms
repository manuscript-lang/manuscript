// Guard: iterator chains over records and strings fuse into one loop (#4185).
type Row {
	id Int
	name String
}

fn main() Void {
	var rows List[Row] = []
	for i in 0..20000 {
		rows.append(Row(i, f"name{i % 311}"))
	}

	total := rows.filter(fn(r Row) Bool => r.id % 3 == 0).map(
		fn(r Row) Int => (r.name.length())
	).sum()
	text := "the quick brown fox jumps over the lazy dog ".repeat(200)
	words := text.split(" ").filter(fn(w String) Bool => w.length() > 3).map(
		fn(w String) Int => w.length()
	).sum()
	print(f"{total} {words}")
}
