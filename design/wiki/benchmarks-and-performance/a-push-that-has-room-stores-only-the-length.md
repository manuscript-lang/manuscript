# A push that has room stores only the length

`xs.append(v)` is `take slot`, `list.push`, `put slot`: a loop of pushes stored the list's pointer, length and capacity back to the slot on every pass. LLVM cannot drop the pointer and capacity stores: the slot's address goes to the cold grow path, and the values come round the loop in registers, so it cannot show they equal what the slot holds. Checked Rust stores only the length.

`mir_expand` now expands a push that goes straight back to the slot it was taken from (the `take` right before, the `put` right after, nothing else reading either) into two paths: the cold grow path puts the whole list, the path with room pushes the element and puts with the length leaf only (`put`'s `imm` names the leaf, `emit_store` writes just that one). A `put` of a push from anywhere else keeps the whole header.

Measured (callgrind, all 23 suite programs): `lz` -2.3%, `graph` -0.8%, `exprparse` -0.4%; `dispatch` +0.8% instructions (one register move in a 20M-iteration loop, wall time equal). `lz`'s `decompress` copy loop goes from 19 to 17 instructions per element (checked Rust: 11); the rest is the `start + k` overflow check, the signed-index bounds check with its jump over the negative-index block, and a reload.

Not done: a cold flag on the negative-index block changes nothing (LLVM keeps the jump over it); a push whose list lives behind another list's element or a record field (`take` is not adjacent) still stores all three.
