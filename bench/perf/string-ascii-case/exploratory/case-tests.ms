import expect_equal from "@std/test.ms"

fn prefix(pattern: String, length: Int) String:
    let repeated = pattern.repeat((length + 7) / 8).get()
    return repeated.slice_scalars(0, length).get()

test "ASCII case conversion preserves exact content and input across result sizes":
    for length in [0, 1, 2, 15, 16, 17, 31, 32, 128, 4096, 1048576]:
        let mixed = prefix("aZ09_-.\u{0}", length)
        let upper = prefix("AZ09_-.\u{0}", length)
        let lower = prefix("az09_-.\u{0}", length)
        try expect_equal(mixed.upper(), upper.clone())
        try expect_equal(mixed.lower(), lower.clone())
        try expect_equal(upper.upper(), upper)
        try expect_equal(lower.lower(), lower)
        try expect_equal(mixed, prefix("aZ09_-.\u{0}", length))

        let controls = prefix("09_-.\u{0}\t\n", length)
        try expect_equal(controls.upper(), controls.clone())
        try expect_equal(controls.lower(), controls)

test "whole string Unicode mapping preserves expansions and contextual sigma":
    try expect_equal("straße".upper(), "STRASSE")
    try expect_equal("straße".lower(), "straße")
    try expect_equal("İ".upper(), "İ")
    try expect_equal("İ".lower(), "i\u{307}")
    try expect_equal("ΟΣ".lower(), "ος")
    try expect_equal("ΟΣΑ".lower(), "οσα")
    try expect_equal("AΣ\u{301}".lower(), "aς\u{301}")
    try expect_equal("AΣ\u{2060}A".lower(), "aσ\u{2060}a")

    let prefix = "a".repeat(1048576).get()
    let input = prefix + "ßİ ΟΣ"
    try expect_equal(input.upper(), "A".repeat(1048576).get() + "SSİ ΟΣ")
    try expect_equal(input.lower(), prefix + "ßi\u{307} ος")
    try expect_equal(input, prefix + "ßİ ΟΣ")
