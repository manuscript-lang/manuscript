// conform: tags=testing
// conform: phase=test
import fake from "@std/test/test.ms"

fn helper() Int:
	return 1

test "not a boundary":
	fake(helper, fn: 2, fn: return ok())?
