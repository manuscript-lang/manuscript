//! Local-zone checks run in a child so the process-global TZ never changes under other tests.
use ms_rt as _;
use ms_std_time::core_time::{calendar, from_calendar, parse_timestamp};

#[test]
fn short_dst_roundtrip() {
    const MARKER: &str = "MS_TIME_SHORT_DST_CHILD";
    if std::env::var_os(MARKER).is_none() {
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "short_dst_roundtrip", "--nocapture"])
            .env(MARKER, "1")
            .env("TZ", "STD0DST,M3.2.0/0,M3.2.0/4")
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        return;
    }
    // The whole DST interval lies between the former +/-one-day probes.
    // Cover the unique interval, the skipped hour, the repeated hour and both sides.
    for (day, hour, utc) in [
        (9, 2, "2024-03-09T02:00:00Z"),
        (10, 0, "2024-03-10T00:00:00Z"),
        (10, 1, "2024-03-10T00:00:00Z"),
        (10, 2, "2024-03-10T01:00:00Z"),
        (10, 3, "2024-03-10T02:00:00Z"),
        (10, 4, "2024-03-10T04:00:00Z"),
        (11, 2, "2024-03-11T02:00:00Z"),
    ] {
        let expected = parse_timestamp(utc.as_bytes()).unwrap();
        assert_eq!(
            from_calendar(2024, 3, day, hour, 0, 0, 0, "Local").unwrap(),
            expected,
            "day={day}, hour={hour}"
        );
    }
    let stamp = parse_timestamp(b"2024-03-10T01:00:00Z").unwrap();
    let c = calendar(stamp, "Local").unwrap();
    assert_eq!((c.civil.hour, c.offset_seconds), (2, 3600));
}
