import Timestamp from "@std/time.ms"

// A fixed clock: the same type and signature as `@std/time.ms`.
export fn now() Timestamp:
    return Timestamp(seconds: 86400, nanos: 0)
