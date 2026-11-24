[Wiki](../index.md) › [Tooling and docs](index.md)

# Preserve OS argument identity before dispatch

Verified: lossy OS argument conversion can map a nonexistent byte path to a different, existing replacement-character filename, so `check` reports success for the wrong input. Reject invalid UTF-8 before dispatch rather than replacing argument bytes.

Apply when: changing CLI argument decoding or path identity.
Evidence: entry point, collision regression, [argument requirement](../../../documentation/developer-tooling/implementation.md).
Verify: an invalid-byte argument returns usage status 2 even when its lossy spelling exists; a genuine UTF-8 replacement-character filename remains accepted.

The same boundary applies after manifest escape decoding: hex/octal bytes must form valid UTF-8 before becoming source, entry or alias paths. Lossy decoding can otherwise select a real U+FFFD filename. Manifest regressions preserve valid multibyte byte escapes and explicit replacement characters while rejecting invalid encodings.

URI percent escapes require exactly two ASCII hex digits before numeric conversion: integer parsers may also accept a leading `+`, decoding `%+A` as a newline. URI decoder tests cover every ASCII digit pair; protocol regressions require malformed requests to return Invalid params while a valid `%2B` filename still receives hover information.

Argument reordering must preserve positional meaning too: moving the first input out of `--` can turn `-input.ms` back into an option or `--help` into a help request. Keep its path spelling unambiguous and test options before the separator through the actual CLI; the regression checks existing and missing paths, JSON and normal help.
