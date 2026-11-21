[Wiki](../index.md) › [Compiler and build](index.md)

# C `ms check` answers only what the corpus diff proves

Verified 2026-11-21: `ms_check_run` (`compiler/src/check_cmd.c`, behind `ms_tool_check` for the Manuscript front and `ms_cmd_check` in the C driver) prints exactly what the Rust `ms check FILE.ms [--json]` prints, or returns a handover and the Rust command runs. A pass with no diagnostics proves nothing for a function the C body pass does not cover, so a module is answered only when every function and constant has `body_checked`, it has no impl or test, and none of the features in `check_unported` (generics, externs, field defaults, prelude imports, public-signature exposure) appears. Each entry in that list is a check with no C port; its port removes the line.

Two traps found by `compiler/tests/check-cmd-diff.sh` (the whole fixture corpus, text and `--json`, output and status): the C checker built no `fix` for several diagnostics, so `--json` with any diagnostic hands over; and `ms_render_text` sorts by position while the Rust command keeps the checker's order unless every diagnostic is a syntax error, so a list not already in position order hands over. The first census served 11% of 5,629 files with 119 wrong answers (UBSan `memcpy(NULL, 0)` in `ty_resolve_fn`, missing declaration checks); the guards brought the wrong answers to 0.

Apply when: porting a checker pass (delete its `check_unported` line only when the script shows no difference), or adding a case where C would answer instead of Rust. The script takes about 20 minutes; run it with `JOBS=16`.
Evidence: `compiler/tests/check-cmd-diff.sh`; the plan for the Manuscript front is `/mnt/project-files/c-cli/ms-front-plan.md`.
