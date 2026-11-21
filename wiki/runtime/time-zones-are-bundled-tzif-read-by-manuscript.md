[Wiki](../index.md) › [Runtime](index.md)

# Time zones are bundled TZif data read by Manuscript

Decision (Chinmay, 2026-11-20, C rewrite workstream W10): zone names resolve in `src/stdlib/internal/zone.ms` from IANA data bundled in `src/stdlib/internal/tzdata.ms`; no zone library (the Rust `jiff` crates are gone). The time natives take an offset and an abbreviation, never a name.

Verified: the Manuscript reader agrees with Python `zoneinfo` on 965,773 of 965,774 instants over every zone (the one difference is the exact last transition of `America/Ojinaga`), with Go's `time` vectors (`time-zones.ms`), and on 1.2M local-time lookups except six `America/Nuuk` times in which `zoneinfo` returns an offset that is not valid at the instant it picks.

- Data: `ms run tools/tzdata.ms -- /usr/share/zoneinfo/tzdata.zi > src/stdlib/internal/tzdata.ms` compiles the package's `tzdata.zi` with `zic -b slim`, stores each distinct zone once (base64) under all its names. Regenerating with the same release is byte-identical. The Ubuntu file is the rearguard form; offsets match.
- Reader: validates TZif version 2 or later, binary-searches the 64-bit transitions in the raw bytes, and applies the POSIX footer after the last transition (`Mm.w.d`, `Jn`, `n`, times that are negative or above 24 hours). A time skipped or repeated by a transition gets the offset before it; the offset search looks at every transition within 18 hours, because a daylight-saving interval can be shorter than the old one-day probes (`TZ=STD0DST,M3.2.0/0,M3.2.0/4`).
- `Local`: two small natives report `TZ` or the `/etc/localtime` link (`msstd_time_system_zone`) and the file itself; Windows reports its zone key and Manuscript maps it with `windows_zones.ms` (CLDR 2021a, ported from `jiff`). The Windows path is not exercised on Linux CI; run `Local` on a Windows runner when touching it.
- Reading `/etc/localtime` from Manuscript would add `std.fs.read` to every `calendar` caller, so the OS reads stay in the natives.

Apply when: changing `@std/time` zones, the data tool, or `Local`.
Evidence: [zone.ms](../../src/stdlib/internal/zone.ms), [time-zones.ms](../../tests/conformance/fixtures/e2e/stdlib/time-zones.ms), [tzdata.ms](../../tools/tzdata.ms).
