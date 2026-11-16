// ms: swap "@std/time.ms"

import Timestamp from "@std/time.ms"

export NOW_TEXT := "1970-01-02T00:00:00Z"

// Only `now` is swapped; every other name in `@std/time.ms` keeps the original.
export fn now() Timestamp:
	return Timestamp(seconds: 86400, nanos: 0)
