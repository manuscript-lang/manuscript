// conform: tags=diagnostics
// conform: phase=check
fn bad() Void {
	void
}

import List from "@std/collections/collections.ms"
// expect-error: MS2003 7:8-7:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 7:1-8:1 ""
