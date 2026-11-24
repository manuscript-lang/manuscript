// conform: tags=testing,tier-stdlib,scope-cleanup
// conform: phase=test
import (
	TemporaryDirectory, temporary, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

fn note(var dir TemporaryDirectory, name String = "note", text String = "hi") Void!:
	write_file(f"{dir.path()}/{name}", text).wait()?
	return ok()

test "an omitted default does not copy an earlier var resource argument":
	var dir = temporary("manuscript-default-resource-")?
	note(dir)?
	note(dir, name: "other")?
	note(dir, "third", "text")?
	expect_equal(dir.path().is_empty(), false)?
