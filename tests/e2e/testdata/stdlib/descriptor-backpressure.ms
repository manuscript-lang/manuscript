import (
    expect_equal, expect_ok, expect_true from "@std/test/test.ms",
    spawn from "@std/os/process.ms",
    milliseconds, monotonic from "@std/time.ms",
)

// The child reads nothing for a second, so a writer that never waited would queue all 8 MiB and return at once.
test "a descriptor write waits while the reader is slow":
    child := try spawn("sh", ["-c", "sleep 1; wc -c | tr -d ' '"])
    chunk := ("x".repeat(1024 * 1024) | try expect_ok).to_bytes()
    var input = child.stdin()
    started := monotonic()
    for index in 0..8:
        try input.write(chunk.clone())

    waited := monotonic().difference(started)
    try expect_true(waited.compare(milliseconds(500)) > 0)
    try input.close()

    count := try child.stdout().next()
    try expect_equal(count.get("".to_bytes()), "8388608\n".to_bytes())
