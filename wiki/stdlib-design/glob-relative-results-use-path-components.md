[Wiki](../index.md) › [Standard-library design](index.md)

# Glob relative results use path components

Verified: `glob(".", GlobOptions(patterns: ["*.txt"]))` returned no matches for
an existing `a.txt` because the relative-path helper treated `.` as a literal
prefix and turned the result into `../txt` (#3299). Relative parent queries had
the same coordinate mismatch. Byte offsets also dropped the first filename
byte beneath a Windows volume root.

Anchor the query root once with the existing lexical absolute-path helper, then
subtract common path components. Do not resolve filesystem links or count a
root as one separator byte. Keep patterns, excludes, callbacks, and returned
paths in their documented forms; output always uses `/` separators.

Apply when: changing filesystem glob traversal roots or relative result paths.
Verify: `relative_paths_keep_whole_components` covers component boundaries and
the host volume root; `glob_relative_roots_match_the_same_files_as_absolute_roots`
uses a child process with an isolated cwd; `fs-glob-relative.ms` exercises the
public API. Never mutate the parallel Rust test runner's process cwd.
