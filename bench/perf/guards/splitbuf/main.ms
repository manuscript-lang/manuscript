// Guard: a `split` whose pieces are read in place lives in the frame (no malloc or free
// per call) when it has at most eight pieces at a one-byte separator.
fn main() Void {
	line := "2026-11-12T13:25:11Z ERROR GET /api/v3/item/1758 503 12"
	var total = 0

	for i in 0..100000 {
		f := line.split(" ").collect()
		total += (f[5].parse_int() or 0) + f[3].length()
	}

	print(f"{total}")
}
