# Perf bash, 2026-11-18: paths, URLs and globs

Base `main` `a27f79be`, Release `ms` from `make build`, 4 vCPU shared Linux VM. Scratch probes (not committed) over 500k generated paths and URLs, Manuscript against Go (`path`, `net/url`) with the same checksums; ms before and after the change, best of 5 runs for the last three rows, one run for the rest (the VM is noisy; the gaps below are well outside the noise).

| Probe (500k items), ms | Before | After | Go |
| --- | ---: | ---: | ---: |
| `normalize` (with `..`) | 142 | 64 | 154 |
| `normalize` (already clean) | 57 | 26 | 97 |
| `join` (3 parts) | 249 | 150 | 187 |
| `extension` | 43 | 23 | 14 |
| `dirname` | 51 | 39 | 129 |
| `relative` | 465 | 175 | 182 |
| `url.parse` | 248 | 122 | 160 |
| `url.format` | 500 | 107 | 78 |
| `url.resolve` | 473 | 196 | 162 |
| `query.format` | 90 | 47 | 220 |

## What changed

- Path: `normalize` appends contiguous runs of the input instead of one segment at a time; `is_clean` jumps by separator; `join` uses one `join("/")` when no part is empty; `relative` borrows views.
- URL: escaping uses a 256-entry rule table with a no-escape fast path, and `set_path`/`set_fragment` skip re-escaping already canonical text.
- Glob: new compiled `path.Glob` (`compile_glob`) matched many times; `matches_glob` is now compile plus match. The NFA keeps its position set in fixed stack bitsets for patterns and values under 128 characters, and the heap otherwise.

- URL format and resolve: `render` output is parsed back only when the host or scheme is not plain (unreserved host bytes with an optional numeric port, a valid scheme, no path that could be re-read as an authority); `format_shortcut_matches_reparse` compares both paths over about 1.2M combinations of tricky components and must stay identical. `resolve` no longer renders the base.
- Path `relative` walks both paths component by component with views and one builder instead of splitting into lists; output was identical to the previous build over 20,000 random pairs in both dialects.

## Still behind Go

`url.format` (1.4x) and `url.resolve` (1.2x) still allocate a `Url` of owned vectors per call.
