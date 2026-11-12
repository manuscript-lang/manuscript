# Rejected full-output reservation probe

This preliminary candidate reserved `2 * input.length()` byte values for the complete hex result before converting to Bytes and UTF-8. It improved time, but the exec-specific 1MiB-input peak-RSS control grew from approximately 9,764KiB to 13,824KiB. The final implementation instead uses bounded 16KiB ASCII batches.

`hex.ms` retains the rejected function. `samples.json` and `aa.json` are the original preliminary measurements; `format-confirm.json` checks the formatted probe. These are not final-implementation results. `rss-exec.json` contains the meaningful after-exec memory observations. The earlier `rss.json` used wait4 high-water RSS, which can inherit the Python parent's fork-time peak; it is retained as a rejected diagnostic and is not used for the memory conclusion. The parent benchmark README identifies the retained implementation and its separate results.
