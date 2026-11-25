[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A per-declaration lookup must not walk the module or the source text

Two lookups cost the size of the file for every declaration, so lint and check of a file with thousands of declarations were quadratic: the effects scan found the lines above a declaration by counting newlines from the start of the file (`ms_directives_above`), and the ownership pass found a constructed type's declaration by scanning the module's declarations (`ms_own_look_field`, once per constructor argument). The first now reads a per-module table of line offsets built once, the second goes through the type's definition. `ms lint` of 4000 small types fell from 1117 to 88 ms (`check` 314 to 86 ms) and of 4000 functions from 252 to 79 ms.

Lesson: generate a file with 1000 and 4000 items (types, functions, calls) and compare times; the ratio must be near 4. A callgrind of the 1000 case shows `memchr` or a decl loop at the top when a lookup scans.
