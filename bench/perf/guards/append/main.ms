// Guard: `s += piece` on a growing string records the room left in the block, so an
// append that fits asks neither the allocator nor a runtime call to copy a short piece.
fn main() Void {
	var s = ""
	for i in 0..200000 { s += "ab" }

	var t = "head-"
	for i in 0..20000 { t += "xyz," }
	print(f"{s.length()} {t.length()}")
}
