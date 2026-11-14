// expect-mir-order: "call @first" "clone 1" "str.bytes"
// Both optimized string scans must own a snapshot of an unproven borrowed receiver.
fn first(words: List[String]) String:
    return words[0]

export fn main() Int:
    words := ["aé😀"]
    var sum = 0
    for c in first(words).scalar_values():
        sum += c
    for c in first(words).chars():
        sum += c.length()
    return sum - 128845
