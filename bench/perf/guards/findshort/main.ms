// Guard: `contains` of a needle between spaces in a log line scans for one of its
// uncommon bytes, not for the space every word starts with.
fn main() Void {
	line := "2026-11-12T13:25:11Z ERROR GET /api/v3/item/1758 503 12"
	var hits = 0
	for i in 0..100000 {
		if line.contains(
			" POST /api/v2/item/17"
		) or line.contains(" 503 ") { hits += 1 }
	}
	print(f"{hits}")
}
