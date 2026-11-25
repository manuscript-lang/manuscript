# List fusion matches the loop shapes real chains produce

`opt_fuse` first matched only a bare builder loop feeding a bare reader loop, so `xs.map(f).filter(g).sum()` in a loop (checked multiply, checked add) never fused: every stage still built its list (62.9M instructions for 2000 rounds over 1000 elements).

- A loop that can fault has exit blocks: a fault edge leaves the function, pausing unwinding, dropping the live lists and returning. The reader's body is now the blocks that lead back to its header; blocks it only leaves by must end the function (`reader_body`), and the list's drops there and after the loop are deleted with the list.
- The builder's fault exit takes the slot and drops the half-built list (`take S; drop`). The list no longer exists after fusion, so `builder_slot` accepts that pair outside the loop and `mark_dead` removes it.
- The `msrt_unwinding` test after a call exists only to see a parked fault. `opt_fuse_step` clears the ones that cannot fire (`opt_unwind_sites`, `opt_unwind_thread`, `opt_simplify`) before matching; with them, every call site split its block and no loop looked plain.
- Result: that chain 62.9M to 24.9M instructions, allocations from 2000 per round to the source's own doubling (`tests/checks/ownership-counts/chain_fusion.ms`); `graph` -9.8%. `hashing` +3.6% instructions with equal wall time: fewer unwinding tests in `sha256`, then a different LLVM schedule; not fusion.
- Still unfused: owned elements (`String` pieces, so `fields_by`/`split` lists feeding a `for`), which is why `wordfreq` and `report` did not move. A `fields_by` loop that walks the text like the split loop is the next step.
