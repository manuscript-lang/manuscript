import panic from "@std/core.ms"
import (bit_and, bit_or, bit_xor, bit_not, shift_left, count_ones, trailing_zeros) from "@std/math/math.ms"

# A set of small non-negative integers stored one bit each: 8 bytes per 64 candidates, with O(1) add, remove and contains.
# Indexes must be 0 through 1073741823 (a 128 MiB bitmap); other indexes fault, so the set never grows without bound by accident.
# Written in Manuscript; clone() makes an independent copy.
# Use it for visited marks, flags, and dense id sets; use Set for sparse or non-integer members.
export type BitSet:
    # Bitmap words, 64 members each, grown on demand. Internal state: use the operations, not this field.
    words: List[Int] = []

impl BitSet:
    # Adds an index; faults when it is negative or above 1073741823.
    var fn add(index: Int) Unit:
        if index < 0 or index > 1073741823:
            panic("BitSet: index must be between 0 and 1073741823, found {index}")

        let word = index / 64
        while self.words.length() <= word:
            self.words.append(0)
        self.words.set(word, bit_or(self.words.get(word), shift_left(1, index % 64)))

    # Removes an index; absent and out-of-range indexes change nothing.
    var fn remove(index: Int) Unit:
        if index < 0 or index / 64 >= self.words.length():
            return

        let word = index / 64
        self.words.set(
            word,
            bit_and(
                self.words.get(word), bit_not(shift_left(1, index % 64))
            )
        )

    # Reports whether the index is a member; out-of-range indexes are not members.
    fn contains(index: Int) Bool:
        if index < 0 or index / 64 >= self.words.length():
            return false

        return bit_and(self.words.get(index / 64), shift_left(1, index % 64)) != 0

    # Returns the number of members.
    fn length() Int:
        var total = 0
        for word in self.words:
            total += count_ones(word)
        return total

    # Reports whether the set has no members.
    fn is_empty() Bool:
        for word in self.words:
            if word != 0:
                return false
        return true

    # Removes every member and releases the bitmap.
    var fn clear() Unit:
        self.words = []

    # Returns the smallest member that is at least `from`, or `none` when there is none.
    fn next(from: Int = 0) Int?:
        var start = from
        if start < 0:
            start = 0

        var word = start / 64
        if word >= self.words.length():
            return none

        var bits = bit_and(self.words.get(word), shift_left(-1, start % 64))

        while true:
            if bits != 0:
                return word * 64 + trailing_zeros(bits)

            word += 1
            if word >= self.words.length():
                return none

            bits = self.words.get(word)

        return none

    # Returns a new list of the members in ascending order.
    fn values() List[Int]:
        var out: List[Int] = []

        for word in 0..self.words.length():
            var bits = self.words.get(word)

            while bits != 0:
                let low = trailing_zeros(bits)
                out.append(word * 64 + low)
                bits = bit_and(bits, bit_not(shift_left(1, low)))

        return out

    # Returns a new set of the members of either set.
    fn union(other: BitSet) BitSet:
        return self.combine(other, 0)

    # Returns a new set of the members of both sets.
    fn intersection(other: BitSet) BitSet:
        return self.combine(other, 1)

    # Returns a new set of the members of this set that are not in `other`.
    fn difference(other: BitSet) BitSet:
        return self.combine(other, 2)

    # Returns a new set of the members of exactly one of the sets.
    fn symmetric_difference(other: BitSet) BitSet:
        return self.combine(other, 3)

    # Merges words pairwise; `mode` 0 is union, 1 intersection, 2 difference, 3 symmetric difference.
    fn combine(other: BitSet, mode: Int) BitSet:
        var out: List[Int] = []
        var count = self.words.length()
        if other.words.length() > count:
            count = other.words.length()

        for word in 0..count:
            var left = 0
            if word < self.words.length():
                left = self.words.get(word)

            var right = 0
            if word < other.words.length():
                right = other.words.get(word)

            var merged = bit_or(left, right)
            if mode == 1:
                merged = bit_and(left, right)
            if mode == 2:
                merged = bit_and(left, bit_not(right))
            if mode == 3:
                merged = bit_xor(left, right)
            out.append(merged)

        return BitSet(words: out)

    # Reports whether every member of this set is in `other`.
    fn is_subset_of(other: BitSet) Bool:
        for word in 0..self.words.length():
            let right = other.words.get(word, 0)
            if bit_and(self.words[word], bit_not(right)) != 0:
                return false

        return true

    # Reports whether every member of `other` is in this set.
    fn is_superset_of(other: BitSet) Bool:
        return other.is_subset_of(self)

    # Reports whether the sets share no member.
    fn is_disjoint_from(other: BitSet) Bool:
        var count = self.words.length()
        if other.words.length() < count:
            count = other.words.length()
        for word in 0..count:
            if bit_and(self.words[word], other.words[word]) != 0:
                return false
        return true
