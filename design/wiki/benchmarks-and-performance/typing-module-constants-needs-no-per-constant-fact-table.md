[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Typing module constants shares one fact table per module

`body_constant_type` allocated and zeroed a node-indexed fact table the size of the whole module for every constant it typed, so a module with many constants cost constants times module size. `ms check src/stdlib/data/html.ms` spent half its 304M instructions in that `memset` and peaked at 159 MB. The table is now allocated once per module (`MsModuleInfo.constant_scratch`): initializers own disjoint nodes, so one table serves them all. The same check fell from 150 ms and 159 MB to 35 ms and 18 MB.

Lesson: profile `ms check` of a stdlib file, not only hello; a per-item allocation sized by the container is invisible on small programs.
