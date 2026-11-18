# Perf bash, 2026-11-18: paths, URLs and globs

Base `main` `a27f79be`, Release `ms` from `make build`, 4 vCPU shared Linux VM. Scratch probes (not committed) over 500k generated paths and URLs, Manuscript against Go (`path`, `net/url`) with the same checksums; ms before and after the change, one run each (the VM is noisy; the gaps below are well outside the noise).

| Probe (500k items), ms | Before | After | Go |
| --- | ---: | ---: | ---: |
| `normalize` (with `..`) | 142 | 64 | 154 |
| `normalize` (already clean) | 57 | 26 | 97 |
| `join` (3 parts) | 249 | 150 | 187 |
| `extension` | 43 | 23 | 14 |
| `dirname` | 51 | 39 | 129 |
| `relative` | 465 | 283 | 182 |
| `url.parse` | 248 | 122 | 160 |
| `url.format` | 500 | 221 | 78 |
| `url.resolve` | 473 | 491 | 162 |
| `query.format` | 90 | 47 | 220 |

## What changed

- Path: `normalize` appends contiguous runs of the input instead of one segment at a time; `is_clean` jumps by separator; `join` uses one `join("/")` when no part is empty; `relative` borrows views.
- URL: escaping uses a 256-entry rule table with a no-escape fast path, and `set_path`/`set_fragment` skip re-escaping already canonical text.
- Glob: new compiled `path.Glob` (`compile_glob`) matched many times; `matches_glob` is now compile plus match. The NFA keeps its position set in fixed stack bitsets for patterns and values under 128 characters, and the heap otherwise.

## Still behind Go

`url.format` (2.8x), `url.resolve` (3x) and `relative` (1.5x) each still validate by round trip or allocate per segment; not fixed here.
