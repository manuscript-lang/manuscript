# A slot that is only loaded and stored gets its own alloca

The emitter let slots that are never live together share one `%cell` alloca to save stack. One slot whose address went to a call (`msrt_list_extend(ptr %cell0, ...)`, `msrt_slot_eq`) made the whole alloca escape, so LLVM kept every other occupant in memory too: in `lz`'s `decompress` loop the output list's three header words were stored to the frame on every `push`, 3 of 15 instructions per element.

`mir_cell_conflicts` now marks a slot `promotable` when every use is `load`, `take`, `store`, `put`, a constant field offset or a copy, and the emitter leaves such slots out of the pool, so each gets an alloca of its own that SROA turns into registers. Measured (callgrind): `lz` -1.3%, `wordfreq` -1.7%, `pargroup` -1.2%, `concat` -1.7%, `objgraph` -0.3%, `exprparse` -0.4%.

A pooled slot joins only a cell of its own size. Best of first-fit put a 16-byte string view into an 88-byte cell whose address a call took; LLVM then kept the view's stores (`grep` +0.45%). Equal sizes keep a view with other views, which SROA still promotes.

Cost: `report` +0.41% and `jsonsum` +0.12%, register choice in loops that are not about slots (spills move, nothing structural: the per-instruction diff is scattered over the loop). Wall time of `report` is equal within noise (146-150 ms both). Frames grow where a pooled slot no longer shares a larger cell.
