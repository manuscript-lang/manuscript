[Wiki](../index.md) › [Tooling and docs](index.md)

# CLI durations truncate each component exactly

Verified: accumulating fractional duration components as floats can round a value below the benchmark minimum up to 1ms and turn two sub-nanosecond components into a positive fuzz budget. CLI duration parsing follows the existing `time.parse_duration` contract: truncate each component to nanoseconds before summing, and preserve the full signed range.

Apply when: changing `--timeout`, `--fuzz`, `--time`, or their duration parser.
Evidence: [standard duration contract](../../stdlib/time.ms), [parser and integer-ratio oracle](../../crates/ms-cli/src/duration.rs), [option validation regression](../../crates/ms-cli/tests/cli_errors.rs).
Verify: `0.5ns0.5ns` parses as zero, `0.999999999999999999ms` as 999999ns, and the CLI rejects those as a positive fuzz budget and a benchmark duration of at least 1ms respectively.
