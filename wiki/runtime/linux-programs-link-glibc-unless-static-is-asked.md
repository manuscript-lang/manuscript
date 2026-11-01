# Linux programs link glibc unless `--static` is asked

Decision (user, 2026-11-01): Linux programs link the system glibc dynamically; musl is linked only with `--static`.

Why: static musl's resolver looks up `/etc/hosts` case-sensitively (`lookup("LocalHost")` failed), and its NSS, locale and allocator differ from what Linux users expect. Verified: the same program resolves under glibc and fails under `--static`.

Mechanism: `cargo xtask runtime` builds `libms_native.a` for `<arch>-unknown-linux-gnu` and `libms_native_musl.a` for musl; `ms` embeds both. The gnu archive defines `_start` (`crates/ms-native`), so lld links `libc.so.6` and `libm.so.6` (nothing else) found in system directories (`MS_LIBC_DIR` adds more) with no `libc6-dev`. glibc 2.34 or newer is required (it runs `.init_array` and merges pthread/dl). C-fixture runtimes in tests define no entry and link musl through `link_libc`.

Verify: build and run a program with and without `--static`; `file` shows dynamic vs static.
