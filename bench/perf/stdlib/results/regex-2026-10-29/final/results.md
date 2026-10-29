Median of 7 alternating runs of 3 samples; all 17 cases and operation counts verified.

| operation | ops | before ns/op | after ns/op | after/before |
|---|---:|---:|---:|---:|
| regex.captures_all.0 | 1 | 34.48 | 30.69 | 0.890x |
| regex.captures_all.1 | 1 | 609 | 532.6 | 0.875x |
| regex.captures_all.128 | 1 | 6.738e+04 | 5.547e+04 | 0.823x |
| regex.captures_all.2000 | 1 | 1.021e+06 | 8.746e+05 | 0.857x |
| regex.replace_template.0 | 1 | 35.99 | 37.13 | 1.031x |
| regex.replace_template.1 | 1 | 546.8 | 506.5 | 0.926x |
| regex.replace_template.128 | 1 | 5.801e+04 | 5.725e+04 | 0.987x |
| regex.replace_template.2000 | 1 | 8.919e+05 | 8.148e+05 | 0.914x |
| regex.replace_template.mixed_long_short.2000 | 1 | 1.958e+06 | 1.903e+06 | 0.972x |
| regex.replace_template.literal.1 | 1 | 421.8 | 192.6 | 0.457x |
| regex.replace_template.literal.2000 | 1 | 7.135e+05 | 2.477e+05 | 0.347x |
| regex.replace_template.unused_large | 1 | 72.99 | 78.1 | 1.070x |
| regex.named_captures.1 | 1 | 318.4 | 299 | 0.939x |
| regex.named_captures.8 | 1 | 1181 | 1046 | 0.886x |
| regex.find_all | 2000 | 131.4 | 134.1 | 1.020x |
| regex.matches | 10000 | 78 | 76.23 | 0.977x |
| regex.replace_all | 2000 | 115 | 118.1 | 1.027x |
