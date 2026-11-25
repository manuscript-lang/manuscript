[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A check made unchecked must not leave its fault exit behind

Lowering follows every checked instruction with a `fault.site` test and an exit block that closes what is owned. The range pass and the constant rules later turn many checks into plain `iadd`, `imul` or `srem`, which cannot fault, but the test and its exit stayed: the emitter wrote `icmp ne i1 0, 0` and a branch to seven stores, a drop and a resume. In a 200-function program 20% of the optimized IR was these dead exits; the release build of 500 such functions took 4.1 s and 267 MB, and now takes 3.8 s and 246 MB (1000 functions: 8.9 to 8.2 s, 462 to 410 MB).

The simplify fold now makes a `fault.site` false when its operand's defining op lacks `MIR_E_FAULTS`, and the existing constant-branch and unreachable-block passes remove the exit. The rule reads the effect table, not a list of ops.

Release builds are about 90% LLVM (optimizer and code generation) and linear in program size, about 8 ms and 0.4 MB per function of the benchmark shape. Cutting emitted IR is the lever for them; the front end is not.
