// conform: tags=diagnostics,maps,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn main() Void {
	m := Map[String, Int]()
	m.set(1, 2)
}
// expect-error: MS2001 6:7 unknown or ambiguous member set on Map[String, Int]; write m[key] = value or m.add(key, value) to insert or replace a Map entry; available: add, add_default, add_default_from, all, any, clear, clone, contains, entries, filter, find, find_last, fold, fold_right, for_each, get, get_or, is_empty, keys, length, map, map_keys, merge, remove, retain, update, values
