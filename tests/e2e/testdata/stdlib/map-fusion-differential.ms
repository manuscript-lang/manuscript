import expect_equal from "@std/test/test.ms"

// A key whose `clone` is source-defined.
type Tag:
    name: String

impl Tag:
    fn clone() Tag:
        return Tag(name: self.name.clone())

impl Equal for Tag:
    fn equals(other: Tag) Bool:
        return self.name == other.name

impl Hashable for Tag:
    fn hash() Int:
        return self.name.hash()

// Each pair below spells one update twice: in the shape the compiler fuses into a single probe, and
// through a named intermediate that it cannot. The maps must stay equal after every step.

test "fused counter updates match the general path for String keys":
    let words = ["a", "bb", "a", "ccc", "bb", "a", "", "ccc", ""]
    var fused: Map[String, Int] = {}
    var plain: Map[String, Int] = {}

    for index in 0..words.length():
        let w = words[index]
        fused.add(w.clone(), fused.get(w).get(0) + 1)
        fused.add(w.clone(), fused.get(w).get(0) * 2)
        fused.add(w.clone(), fused.get(w).get(0) - index)

        let one = plain.get(w).get(0)
        plain.add(w.clone(), one + 1)

        let two = plain.get(w).get(0)
        plain.add(w.clone(), two * 2)

        let three = plain.get(w).get(0)
        plain.add(w.clone(), three - index)

    try expect_equal(fused.length(), plain.length())
    for word in ["a", "bb", "ccc", ""]:
        try expect_equal(fused.get(word), plain.get(word))

test "fused counter updates match the general path for Int keys and swapped operands":
    var fused: Map[Int, Int] = {}
    var plain: Map[Int, Int] = {}

    for key in [3, 1, 3, 2, 1, 3]:
        fused.add(key, 5 + fused.get(key).get(0))
        fused.add(key, 3 * fused.get(key).get(7))

        let left = plain.get(key).get(0)
        plain.add(key, 5 + left)

        let right = plain.get(key).get(7)
        plain.add(key, 3 * right)

    for key in [1, 2, 3, 4]:
        try expect_equal(fused.get(key), plain.get(key))

test "fused counter updates match the general path for source-defined key types":
    var fused: Map[Tag, Int] = {}
    var plain: Map[Tag, Int] = {}

    for name in ["x", "y", "x", "x", "z", "y"]:
        let tag = Tag(name: name)
        fused.add(tag.clone(), fused.get(tag).get(0) + 1)

        let current = plain.get(tag).get(0)
        plain.add(tag.clone(), current + 1)

    try expect_equal(fused.length(), plain.length())

    for name in ["x", "y", "z", "w"]:
        let tag = Tag(name: name)
        try expect_equal(fused.get(tag), plain.get(tag))

test "fused updates match the general path when the operand reads the map":
    var fused: Map[Int, Int] = {1: 10, 2: 20}
    var plain: Map[Int, Int] = {1: 10, 2: 20}

    // The operand names the map, so the compiler must not fuse; both spellings agree.
    fused.add(1, fused.get(1).get(0) + fused.get(2).get(0))

    let sum = plain.get(1).get(0) + plain.get(2).get(0)
    plain.add(1, sum)
    try expect_equal(fused.get(1), plain.get(1))
    try expect_equal(fused.get(2), plain.get(2))
