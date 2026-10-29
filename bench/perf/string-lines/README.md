# String line splitting

This benchmark measures generated-program runtime for `String.lines()`, including
its result allocation and traversal. Input construction, compilation, process
startup, output, and an initial checked warm-up of each case are outside the timed
region. Every result contributes its line count and byte lengths to a checked
checksum. There is no CI timing threshold.

`compare.py` runs seven alternating before/after pairs. It rejects producer
failures, missing or duplicate cases, changed input sizes or iteration counts,
incorrect checksums, and nonpositive timings. It writes all samples before
printing medians and ranges in nanoseconds per `lines()` call.

## Reproduce

Build the compiler and native runtime at the baseline revision, then preserve the
archive and use the same compiler and source for both executables:

```sh
cargo xtask runtime
cargo build --release --locked -p ms-cli
cp target/ms-native/libms_native.a /tmp/string-lines-before.a
MS_RT_LIB=/tmp/string-lines-before.a target/release/ms build \
    bench/perf/string-lines/main.ms --build-type Release -o /tmp/string-lines-before
```

Apply the runtime patch, rebuild its archive, and build the second executable:

```sh
cargo xtask runtime
MS_RT_LIB="$PWD/target/ms-native/libms_native.a" target/release/ms build \
    bench/perf/string-lines/main.ms --build-type Release -o /tmp/string-lines-after
python3 bench/perf/string-lines/compare.py \
    /tmp/string-lines-before /tmp/string-lines-after /tmp/string-lines-samples.csv
```

The compiler, its embedded pure-runtime helpers, and benchmark source must match
between builds. Copy this directory into the baseline checkout when reproducing
from a revision that predates the harness. Stop other builds and CPU workloads
before timing. Verify the selected backend: Release can fall back to Cranelift
if LLVM tools are unavailable; `--build-type Release` alone does not prove LLVM
was used. Record the host, source revisions, tools, backend, optimization level,
and executable/source/archive hashes with any published results.

The source controls include empty text, adjacent empty lines, tiny and short
unterminated text, LF offsets around 8/16/32-byte search boundaries, increasingly
long LF lines, Unicode with CRLF, and a 1 MiB string without a newline. Output
allocation and copying remain part of this operation's cost.
