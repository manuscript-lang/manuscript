// ms: mock "@std/time.ms" "./fake_clock.ms"
// ms: mock "@std/os/env.ms" "./fake_env.ms"

import (
	expect_equal from "@std/test/test.ms",

	banner from "./greeting.ms",
)

test "banner uses the faked clock and environment":
	expect_equal(banner()?, "hello test-user, it is 1970-01-02T00:00:00Z")?
