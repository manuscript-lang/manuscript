Median of 7 alternating runs of 3 samples; all 17 cases and operation counts verified.

| operation | ops | before ns/op | after ns/op | after/before |
|---|---:|---:|---:|---:|
| regex.captures_all.0 | 1 | 33.02 | 31.44 | 0.952x |
| regex.captures_all.1 | 1 | 587 | 577.1 | 0.983x |
| regex.captures_all.128 | 1 | 6.72e+04 | 6.279e+04 | 0.934x |
| regex.captures_all.2000 | 1 | 1.069e+06 | 1.065e+06 | 0.997x |
| regex.replace_template.0 | 1 | 37.19 | 39.33 | 1.058x |
| regex.replace_template.1 | 1 | 558.7 | 506.7 | 0.907x |
| regex.replace_template.128 | 1 | 6.019e+04 | 5.419e+04 | 0.900x |
| regex.replace_template.2000 | 1 | 9.282e+05 | 8.288e+05 | 0.893x |
| regex.replace_template.mixed_long_short.2000 | 1 | 1.862e+06 | 1.95e+06 | 1.047x |
| regex.replace_template.literal.1 | 1 | 430.9 | 195.9 | 0.454x |
| regex.replace_template.literal.2000 | 1 | 7.152e+05 | 2.506e+05 | 0.350x |
| regex.replace_template.unused_large | 1 | 82.09 | 80.14 | 0.976x |
| regex.named_captures.1 | 1 | 328.2 | 318.5 | 0.970x |
| regex.named_captures.8 | 1 | 1187 | 1147 | 0.966x |
| regex.find_all | 2000 | 133.8 | 144.1 | 1.077x |
| regex.matches | 10000 | 80.54 | 84.15 | 1.045x |
| regex.replace_all | 2000 | 117.5 | 126.8 | 1.079x |
