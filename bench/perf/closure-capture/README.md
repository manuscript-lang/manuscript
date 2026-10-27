# Closure captures

`src/main.ms` makes a closure over a 64 MB record 50 times, calling each ten times, and keeps using the record afterward. Before this change every closure copied the record's list; a non-escaping closure now points at the variable instead.

Run: `ms build bench/perf/closure-capture -o /tmp/cc && time /tmp/cc`

## 2026-10-27, revision 673de042 plus the borrowed-capture change, 4-core Linux x86_64 container

| Build | Wall time |
| --- | --- |
| before (main) | 2.16 s, 2.25 s |
| after | 0.035 s, 0.037 s |
