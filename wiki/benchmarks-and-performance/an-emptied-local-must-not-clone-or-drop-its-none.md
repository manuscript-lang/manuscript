
## String `<` is generated MIR

`msrt_string_compare` is inlined (`rtstr.rs` `compare`): a byte loop over the common prefix of up to 16 bytes, read from any string form (static, inline, heap), then the lengths; longer prefixes call the runtime. String literals are static pointer strings, not inline ones, so a word-compare fast path for inline strings never fires on them. `scmp` went 77.1M to 34.8M instructions (checked C 48.4M); guard `strcmp`.
