# Hexadecimal, Base32 and ASCII85 moved from C to Manuscript (2026-11-25)

Change: the hexadecimal, Base32 and ASCII85 natives in `runtime/std/encoding.c` (about 280 lines of C and six `msstd_encoding_*` externs) became Manuscript in `stdlib/data/encoding.ms`. Base64 stays in C: the runtime itself calls it (the WebSocket handshake, JSON bytes, PEM), so a Manuscript copy would leave two implementations of one behavior. Proposal: [pure codecs in Manuscript](../../../design/proposals/pure-codecs-in-manuscript.md), stage 3.
Baseline: `aef8a7f7`. After: this branch. Same program (`bench.ms`: 40 rounds of encode plus decode over 256 KiB of pseudo-random bytes), same preset, same shared 4-core Linux x86-64 VM, no other build running, 15 alternating runs. Wall time in ms for the whole run, which includes about 8 ms of setup common to both.

| codec | before (C) min / median | after (Manuscript) min / median | ratio |
| --- | --- | --- | --- |
| hexadecimal | 97.0 / 104.3 | 45.7 / 49.9 | 0.47 / 0.48 |
| Base32 | 42.5 / 45.4 | 36.6 / 39.6 | 0.86 / 0.87 |
| ASCII85 encode | 27.5 / 30.0 | 16.0 / 17.2 | 0.58 / 0.57 |
| ASCII85 decode | 19.4 / 21.3 | 17.9 / 18.9 | 0.92 / 0.89 |
| Base64 (unchanged C, control) | 49.7 / 56.0 | 46.5 / 51.3 | 0.93 / 0.92 |

The Base64 row runs the same C in both builds, so it shows the noise of the machine (about 8%).

Callgrind instructions, same program: Base32 752M before, 697M after; ASCII85 encode 298M before, 249M after; ASCII85 decode 290M before, 310M after (1.07x); hexadecimal 421M before, 787M after. Hexadecimal executes more instructions and is still twice as fast: the C allocates and copies the text twice.

Output check: `projects/encoding_oracle` replays 7,036 cases recorded from the C natives (every codec and variant, encode and decode, mutated and cross-variant texts, the byte budget at, below and above the exact size, no limit, a negative limit); every output is identical. The test parses its own hex so the codec under test never decodes its inputs.

Findings, in the order they cost time:

- A first generic bit-accumulator port was 1.5x (Base32) and 1.9x (ASCII85) slower. Whole groups (5 bytes of Base32, 4 of ASCII85) run as one wide integer with the bit natives; the accumulator loop only does the tail.
- Calling a helper that takes the `BytesBuilder` as `var` spills the builder to memory on every append. The group loops append inline.
- Table values need their range visible to the arithmetic check: `masked(digit)` (and with 127) after the validity test removed the overflow checks on the group sums.
- A combined validity test on table lookups is only sound for a bound of the form 2^k - 1. ASCII85 digits go to 84, so the OR of five valid digits can reach 127 and the first version sent most groups down the slow path; the test is now bit 7 of the OR (invalid is 255).
- The ASCII85 alphabet and the reverse tables are integer constants, which lower to static views (`list.const.view`, from the HTML port).
