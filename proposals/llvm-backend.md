# Proposal: LLVM release backend (P4)

Status: **reopened 2026-10-21** (see "Bundled release backend" below); previously **deferred.** The spike gate failed on `collatz`: hand-written LLVM IR (checked ops, atomic poll, `clang -O3`) ran in 355k us against 359k us for Cranelift, 1.0x. `nbody` (1.6x vs C) is the one candidate left; revisit if float-kernel performance becomes a priority. Proposal for the gate in [rust-cranelift-backend.md](rust-cranelift-backend.md) (P4: "a measured gap on real programs justifies LLVM or C emission from the same MIR"). Cranelift stays the default.

## Problem

Cranelift output trails clang -O3 on float-heavy code and is level on integer loops. Same machine, same run, wall time in microseconds, `ms-clif/kernels/*.mir` compiled by `mirc` (Cranelift, `speed`) against `bench/c-backend-estimate.c` built with `clang -O3` (checked arithmetic, polls, bounds checks, same loop structure):

| kernel | Cranelift (min of 7) | C (clang -O3, in-kernel) | ratio |
|---|---:|---:|---:|
| collatz 1M | 359k | 357k | 1.0x |
| sieve 5M | 45k | 40k | 1.1x |
| life 128x128x50 | 38k | 34k | 1.1x |
| matmul 200 | 20k | 15k | 1.3x |
| nbody 200k | 21k | 13k | 1.6x |
| trees d16 x20 | 81k | 56k | 1.4x* |

Geometric mean about 1.2x. An earlier single-run table showed 1.7x; it was noise in the Cranelift runs. Caveats: Cranelift times are whole-process wall times (include startup and allocation); the C estimate has no reference counting or drops (`*` trees is optimistic for C); the C file is hand-written, not emitted from MIR. The real gap is therefore smaller than the table and is not yet measured on MIR-to-LLVM output.

The perf gaps on `bench/results.md` today (`for_list` 7x, `read_line` 10x vs Go) are runtime and MIR issues, not codegen quality, and belong to the perf thread. This proposal does not claim to fix them.

## Proposal

Add crate `ms-llvm`: lowers verified MIR to textual LLVM IR (`.ll`), compiles it with the system `clang` (`-O2`/`-O3`, `-c`) to an object, and hands the object to the existing linker driver. Selected by `ms build --backend llvm` (default `cranelift`).

- No LLVM build-time dependency: no `inkwell`/`llvm-sys`, no LLVM in the `ms` binary or the Cargo lock, no license or size change. `clang` is needed only when the flag is used, and the driver already shells out to `cc`/`clang`.
- Reuses `ms_clif::layout` (leaf flattening, memory layout) and the runtime ABI constants, so value representation and runtime calls cannot drift between backends. Stage 1 depends on `ms-clif` for these; moving layout into a shared crate is a follow-up only if it proves worth it.
- Faults, polls, checked arithmetic map to `llvm.*.with.overflow`, cold branches and `noreturn` runtime calls. Frame pointers kept (`"frame-pointer"="all"`) so fault traces and `ms profile` work. Line tables via `!DILocation` after the scalar subset works.

Stages, each its own PR, each differential-tested against the Cranelift output on the same MIR:

1. `ms-llvm` crate, flag plumbing in `ms-driver`/`ms-cli`, scalar subset (Int/Float/Bool, branches, calls, checked ops, faults), kernels `collatz` and `mul_const`. Gate: output equal to Cranelift, timings recorded.
2. Aggregates and lists: records, alternatives, optionals, list ops, strings, rc `drop`/`copy`. Kernels sieve, life, matmul, nbody, trees.
3. Closures, interfaces, cleanup stack, externs and stdlib calls; run the conformance corpus under `--backend llvm`.
4. Debug info and perf map parity.

## Decision gate

Spike first, before any stage: lower `collatz` and `nbody` MIR to `.ll` (checked ops, polls, bounds checks, no rc) in a throwaway branch and compare in-kernel times with Cranelift on the same machine. Proceed to stage 1 only if the spike is at least 1.3x faster. The table above mixes whole-process Cranelift times with in-kernel C times, so it overstates the gap; the spike replaces it as the evidence. After stages 1 and 2, rerun on real emitted code; if the kernel geometric mean is under 1.2x faster than Cranelift, remove the crate.

Stage 4 is capped: if debug info, perf map and fault-trace parity are not reachable, the backend ships as "no profiling support" only if DESIGN.md decision 5 is amended by the owner.

## Alternatives

- **Do nothing.** Cranelift is within 1.2x to 2.7x of C on kernels, and the runtime gaps dominate real programs today. Cheapest. Reason to not stop here: P4 already commits to the question, and the kernel gap is real and measured, only its size on emitted code is uncertain.
- **`inkwell`/`llvm-sys` bindings.** Direct API, no text round trip. Costs a pinned LLVM install at build time for every contributor and in CI, an LLVM-sized release artifact if linked in, and version churn. Rejected for stage 1; revisit only if text IR compile time becomes the bottleneck.
- **C emission.** Same optimizer via `clang`, but loses precise control of overflow/noreturn semantics and debug info, and was already judged in `bench/c-backend-proposal.md`. LLVM IR is the lower-level target for the same toolchain.
- **Improve MIR optimizations instead.** Complementary and needed regardless (the perf thread). Does not close register allocation, vectorization and LICM gaps.

## Risks

- Text IR for large modules is slow to parse; acceptable for release builds, measured in stage 2.
- Two backends double the surface for codegen bugs; mitigated by differential testing on shared MIR and running the conformance corpus under both.
- Requires a system `clang`, a new prerequisite beyond `cc` for this flag only. Supported version: LLVM 18 or newer, tested in CI on Linux; macOS and Windows availability is unverified and must be settled (and added to `rust-toolchain.md`) before stage 1. Owner of the version policy: the backend thread.

## Bundled release backend (2026-10-21)

Owner direction: Release and MinSizeRel builds use LLVM `-O3`/`-Os`; Debug stays on Cranelift; `ms` stays self-sufficient (no host `clang` required). This supersedes the "system `clang`, flag only" shape above. The earlier gate result stands and still governs the work.

### Facts checked in this checkout

- No LLVM code exists. `ms-clif` is the only backend; `link.rs` shells out to `cc`, and Windows to `clang` plus `lld`. "Bundled linker" is still planned, not shipped.
- The build host has LLVM 18 binaries and `clang` but no static libraries (`libLLVM*.a` absent), so linking LLVM into `ms` needs a source build or a prebuilt archive in CI. Neither is wired up.
- Measured headroom: kernel geometric mean about 1.2x from hand-written C at `-O3` against Cranelift (table above), and the collatz spike was 1.0x. The large Rust gaps in `bench/perf/programs/results.md` (`string_append` 3.7x, `for_list` 3.4x) are runtime and MIR shape; some of `for_list` and `int_eq` is vectorization LLVM would add.

### Plan

0. **Evidence gate (before any bundling work).** Emit textual IR from current MIR for `collatz`, `nbody`, `sieve`, `matmul`, `life`, `trees`, with checked arithmetic, polls, bounds checks and rc, and compile with host `clang -O3`. Proceed only if the geometric mean is at least 1.2x faster than Cranelift and `for_list`/`int_eq` improve. If not, stop and record the numbers here.
1. **`ms-llvm` crate** emitting IR through a vendored, pinned LLVM (C API via a small `unsafe` shim crate, like `ms-rt`), selected by build level. Reuses `ms_clif::layout` and the runtime ABI.
2. **Bundling.** Statically link the LLVM optimizer and codegen for the host target plus `lld` as a library or sidecar; pinned version, built in CI, cached. Measure binary size and build time; the `ms` binary grows by tens of MB and CI by a source LLVM build.
3. **Parity.** Conformance corpus under both backends, DWARF line tables, fault traces, profiling.
4. **Measure** all 31 benchmarks against Go and Rust and update the performance docs with the numbers, whichever way they land.

### Do-nothing case and risks

Doing nothing leaves Cranelift at about 1.2x of C on kernels. The bundle costs a large binary, a long CI build, a license review (Apache-2.0 with LLVM exceptions), and a second backend to keep correct. Mitigation: stage 0 gate, differential testing on shared MIR, Debug stays on Cranelift.
