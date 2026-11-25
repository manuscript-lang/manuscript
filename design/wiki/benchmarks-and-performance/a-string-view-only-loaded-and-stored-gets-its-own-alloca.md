# A string view that is only loaded and stored gets its own alloca

The emitter lets slots that are never live together share one `%cell` alloca to save stack. One occupant whose address went to a call (`msrt_list_extend(ptr %cell0, ...)`, `msrt_slot_eq`) made the whole alloca escape, so LLVM kept every other occupant in memory too.

`mir_cell_conflicts` marks a slot `promotable` when every use is `load`, `take`, `store`, `put`, a constant field offset or a copy. `emit_slot_pool` gives such a string-view cell (`StrData`, the temporary behind an interpolation piece or a literal passed by address) an alloca of its own, which SROA turns into registers, and a pooled slot joins only a cell of its own size (first-fit had put a 16-byte view into an 88-byte cell whose address a call took, so LLVM kept the view's stores: `grep` +0.45%). Measured (callgrind): `wordfreq` -1.7%, `concat` -1.5%, `csvgroup` -1.0%, `logstats` -0.7%, `report` -0.35%, `objgraph` -0.3%, `jsonrt` -0.3%.

Why only views: unsharing every promotable slot also takes `lz` -1.3% (the output list's header words stop being stored on every `push`), but `report` loses 1.2% wall time (min of 21, six alternating runs) for it: its one big `main` gets a different register allocation, and the instruction count rises 0.41%. The rule is no wall-time loss, so the list-slot half is not shipped; the fix is a way to keep promoted slots from adding register pressure in a large function, or a list-header design that does not need a slot per list (see the `lz` gap in `bench/perf/results.md`).

Cost: `exprparse` +0.22% instructions (+0.4% wall, inside the spread) and `jsonsum` +0.12% (wall -1.6%), register choice.
