# ASCII allocating C control and independent review

520 generated ASCII cases passed baseline Manuscript, candidate Manuscript, and allocating C (1,560 checks); the same set passed after rebuilding C with `-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -Wall -Wextra -Werror`. No sanitizer diagnostics. Error checks include exact kind and message.

Six contextual cases have seven alternating triples pinned to CPU4, with equal iteration counts per case calibrated to at least 100 ms on the fastest variant. See `report.json`, `paired-ms.json`, and `metadata.json`. Median paired candidate/baseline ratios:

| Case | Ratio |
| --- | ---: |
| empty | 0.9088 |
| one | 0.9363 |
| ordinary | 1.0072 |
| comma | 0.9622 |
| ascii1024 | 0.3507 |
| ascii65536 | 0.2304 |

Ordinary short-input differences remain neutral against the primary A/A variation. Raw paired ranges are in `paired-ms.json`.

The final optimized C reference uses libc `memchr` searches and exact unquoted-field allocations with `memcpy`; quoted fields use bounded capacity and a scalar escaping/normalization loop. Both encoded fields and the exact final row are allocated. This differs from Manuscript runtime representations and replacement intermediates. Ratios describe these implementations and this harness, not intrinsic language/compiler superiority or a C lower bound. Unicode, arbitrary row structures and parser performance are outside this comparator.

| Case | C ns/call | Baseline/C | Candidate/C |
| --- | ---: | ---: | ---: |
| empty | 34.18 | 4.117 | 3.696 |
| one | 44.72 | 3.382 | 3.159 |
| ordinary | 45.23 | 3.970 | 3.958 |
| comma | 46.85 | 4.663 | 4.405 |
| ascii1024 | 99.41 | 10.426 | 3.610 |
| ascii65536 | 6059.46 | 9.353 | 2.155 |

Independent primary-evidence review recomputed all 23 paired medians from the raw samples (not kept in the tree; rerun `run.py`); every value matched the reported ratio. A/A B/A medians were empty 0.9995, ordinary 0.9898, comma 0.9907, negative 0.9869, ASCII65536 1.0082. Pair ranges are broad (ordinary 0.955–1.275), supporting neutral treatment of small differences and strong gains for the large cases.

Production diff review: validated ASCII delimiter permits equivalent substring search; initial scalar trim and exact backslash-dot behavior remain identical; empty, error ordering, byte budgets, public APIs and CRLF normalization are preserved. Added tests cover relevant Unicode, delimiter, exact-budget and invalid-option behavior. No semantic blocker found. Approval is conditional on the parent completing applicable checks and exact-head CI; this scratch review does not approve an unchecked merge.
