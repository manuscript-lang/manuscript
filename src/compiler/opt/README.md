# src/compiler/opt

The MIR optimiser. `mir_optimize` (`opt.h`) runs the passes in `opt_pipeline.c`, the same for every build type: the early
module steps, up to three rounds of the per-function passes on a copy of each function, and the late steps. Each pass is `opt_<name>.c` (declared in `opt_pass.h`); the
files `opt_util.*` hold the helpers they share. Allowed includes: see `src/layers.txt`.

With `verify`, the module is verified once, after the last step, and the failure is written to `error`.
