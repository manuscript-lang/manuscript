# Compile-time benchmark

`gen.py` writes a deterministic project of about 29k lines in 31 modules (records, alternatives with flat `match`, an interface and `impl`, generics, `Result`/`try`, loops over lists and maps, string interpolation). `run.sh` times the compiler on it and checks the Debug and Release executables print the same checksum.

```sh
MS=./target/release/ms sh bench/perf/compile/run.sh 3   # best of 3
```

Reference run (4 cores, Linux): `check` 0.50s, Debug build 2.0s, Release build 5.4s (LLVM split across cores), Release with `MS_BACKEND=cranelift` 2.4s. Compare numbers from the same machine only; this is a profiling guide, not a gate.

`gen.py OUTDIR [UNITS_PER_MODULE]` scales the project (default 15 units per module).
