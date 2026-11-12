# Fewer allocations need wall time, not just counts

Counting the pieces of a `split` first (one `memchr` pass) so the list is sized once removed one of 4.6 allocations per `logstats` line and 6% of callgrind instructions, yet wall time on 22 MB rose from 103 to 111 ms (min of 25, three runs). The release allocator's free list is cheap and the extra pass over a short line is not. Keep an allocation change only when the same-machine wall time agrees ([benchmark page](../../bench/perf/structural-gaps/README.md)).

Strings of 22 bytes or fewer are inline, so borrowing a short key instead of cloning it saves nothing; check the key length in the benchmark before expecting a gain from a borrowed-key path.
