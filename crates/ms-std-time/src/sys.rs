//! Portable clocks behind the native time wrappers.

/// Seconds and nanoseconds since the Unix epoch; the nanoseconds stay in `0..1e9` before it too.
pub fn realtime() -> (i64, i64) {
    use std::time::{SystemTime, UNIX_EPOCH};
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(d) => (d.as_secs() as i64, i64::from(d.subsec_nanos())),
        Err(e) => {
            let d = e.duration();
            let nanos = i64::from(d.subsec_nanos());
            if nanos == 0 {
                (-(d.as_secs() as i64), 0)
            } else {
                (-(d.as_secs() as i64) - 1, 1_000_000_000 - nanos)
            }
        }
    }
}

/// Nanoseconds since the first reading in this process.
pub fn monotonic_since_start() -> i64 {
    static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
    START
        .get_or_init(std::time::Instant::now)
        .elapsed()
        .as_nanos() as i64
}
