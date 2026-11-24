# Compile time of the compiler

`ms check` and `ms build` of three programs, old binary (`main` a8deb279) against the new one, both release builds on the same machine. Instructions are whole-process callgrind counts (`valgrind --tool=callgrind ms check FILE`); times are the median of 5 to 15 runs, each build of a file edited by a comment so the build cache does not answer.

## 2026-11-14 (x86-64 Linux sandbox, 4 cores, analyze the standard library on demand)

| program | command | before | after |
| --- | --- | --- | --- |
| hello (`print("hi")`) | check, instructions | 317.5M | 167.7M |
| `bench/perf/suite/exprparse/main.ms` | check, instructions | 323.1M | 173.4M |
| `tools/conform.ms` | check, instructions | 846.1M | 362.6M |
| hello | build Debug, instructions | 321.6M | 171.8M |
| `tools/conform.ms` | build Debug, instructions | 1,515.9M | 1,032.0M |
| hello | check, time | 71 ms | 40 ms |
| `tools/conform.ms` | check, time | 183 ms | 86 ms |
| hello | build Debug / Release, time | 109 / 160 ms | 84 / 116 ms |
| `tools/conform.ms` | build Debug / Release, time | 289 / 1072 ms | 185 / 804 ms |

The effect scan and the ownership analysis now cover the project's callables and what they reach; the rest of the standard library is analyzed when lowering or a tool asks (`design/proposals/analyze-the-standard-library-on-demand.md`). What is left in a hello check is parsing and declaring the eager standard modules and checking the bodies of the bundled modules it imports.
