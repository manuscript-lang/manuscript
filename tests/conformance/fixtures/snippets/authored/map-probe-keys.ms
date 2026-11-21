// conform: tags=maps,sets,tier-core
// conform: phase=run
// conform: origin=compiler/src/opt/opt_probe.c
// Lookups the probe pass runs inline: integer and text keys of every length class (inline, one
// block of 16 to 32 bytes, longer, non-matching tails), present and absent, and a set.
export fn main() Int:
    ints := {1: 10, 2: 20, 3: 30, 1000000007: 40, -5: 50}
    texts := {
        "a": 1,
        "bb": 2,
        "fifteen bytes!!": 3,
        "exactly sixteen!": 4,
        "a considerably longer key text": 5,
        "another quite lengthy key string here": 6,
    }
    set := [1, 2, 3, 99].to_set()
    var total = 0
    for k in [1, 2, 3, 1000000007, -5]:
        total += ints[k]
    for k in ["a", "bb", "fifteen bytes!!", "exactly sixteen!", "a considerably longer key text", "another quite lengthy key string here"]:
        total += texts[k]
    for k in [1, 2, 3, 4, 99, 100]:
        if set.contains(k):
            total += 1000
    if ints.contains(7):
        total += 100000
    if texts.contains("a considerably longer key tex"):
        total += 100000
    if texts.contains("another quite lengthy key string herE"):
        total += 100000
    print(total)
    return 0
