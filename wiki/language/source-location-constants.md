# Source-location constants

Chinmay asked for `__LINE__` and `__FILE__` (2026-11-06) to populate with the line number and file name. They are unbound names the checker types (`Int`, `String`) with `Info.native` set, and lowering emits a literal from the use site's position and file. A caller's position uses the existing `caller_site()` parameter default instead.

Trap: `Checker::contextual` treats unbound names as needing context, so a generic call such as `print(__LINE__)` failed to infer `T` until the constants were excluded there.
