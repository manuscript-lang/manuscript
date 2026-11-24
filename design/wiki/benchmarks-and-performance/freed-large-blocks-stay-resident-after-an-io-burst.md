[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Freed large blocks stay resident after an `/io` burst

Verified (2026-11-03, `bench/perf/web`, one serving thread, 64 connections): resident memory goes 8 MB after `/health` load to 111 MB after `/io` load and stays there. Each in-flight `/io` request holds a 1 MiB payload clone and a 1 MiB read result (`write_file_bytes` clones `data`; a shared payload cannot be moved or borrowed to a promise that outlives the call). Two things keep the freed blocks: the runtime's large-block lists (`LARGE_CACHE_LIMIT`) and glibc raising its mmap threshold after the first freed mmap block.

Rejected: pinning the threshold with `mallopt(M_MMAP_THRESHOLD, 128 KiB)` gave 74 MB (31 MB with a 16 MB list cap) but slowed `citm_catalog` parse from about 570 to 380-450 MB/s, because big blocks fault in fresh pages. Capping the lists alone left 104 MB. Removing them left 46 MB.

Apply when: changing the allocator's large-block reuse or file-job buffering. A fix must bound in-flight buffers (park the caller before it clones) or return idle blocks without losing JSON parse reuse; run `bench/tools/json_bench.ms` before and after.
