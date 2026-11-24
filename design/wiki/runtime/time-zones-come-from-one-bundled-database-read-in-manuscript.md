[Wiki](../index.md) › [Runtime](index.md) › Time zones

# Time zones come from one bundled database that `zone.ms` reads

`@std/time` resolves zones in Manuscript (`src/stdlib/internal/zone.ms`) and hands the C natives a resolved offset and abbreviation (`msstd_time_timestamp_calendar`, `_format`, `_from_local`). The data is the same on Linux, macOS and Windows: `src/runtime/std/tzdata.bin`, embedded by `cmake/EmbedBlob.cmake`, read through `msstd_time_zone_data(name)`.

- **Format.** Only the TZif version 2+ block of each zone, plus `windows/<key>` entries (CLDR `windowsZones.xml`, territory 001) whose data is the IANA name. Rebuild it with `tools/tzdata/pack.c` (steps in its header) when IANA publishes a release; the file records the version.
- **Fat, not slim.** zic 2.39 with `-b slim` stopped Gaza's Ramadan rules in 2072 (the system file carries them to 2086), so the database is built with `-b fat`. The footer (POSIX rule) still governs the time after the last transition.
- **Local zone.** `msstd_time_system_zone` says how the host names it (`tz:` TZ setting, `link:` /etc/localtime target, `windows:` registry key); `zone.ms` maps it to a database entry, falls back to a TZ rule such as `EST5EDT,M3.2.0,M11.1.0`, then to the bytes of /etc/localtime, then to UTC.
- **Gaps and folds.** `from_calendar` takes the offset before the transition, as before (the Rust version used jiff's `before`).
- **Checked against.** The lookup algorithm was ported from a Python model that matched `zoneinfo` for offsets, abbreviations and gap/fold resolution on all 498 system zones; `zone.ms` itself has only been type-checked until the compiler runs programs.
