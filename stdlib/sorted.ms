import {range} from "@std/collections.ms"

# Orders two keys: negative when `left` sorts first, zero when equal, positive when `right` sorts first.
fn order[T: Comparable](left: T, right: T) Int:
    return left.compare(Comparable(value: right))

# One key-value pair of a SortedMap.
export type SortedEntry[K: Comparable, V]:
    # The entry's key, which orders it within the map.
    key: K
    # The value stored for `key`.
    value: V

# A map kept in ascending key order, so lookups by position (first, last, floor, ceiling, range) are as cheap as lookups by key.
# Keys use their Comparable order; keys that compare equal are the same key. Replacing a key's value keeps the original key.
# Written in Manuscript as a list of sorted chunks of at most 256 entries: get, contains, floor and ceiling take O(log n);
# add and remove take O(log n) to find the spot plus a shift inside one 256-entry chunk, which stays well under a microsecond per operation up to millions of entries.
# Use clone() for an independent deep copy. Use Map when order does not matter; its operations are O(1).
export type SortedMap[K: Comparable, V]:
    # Sorted chunks of keys; no chunk is empty. Internal state: use the operations, not this field.
    key_chunks: List[List[K]] = []
    # Values parallel to `key_chunks`. Internal state.
    value_chunks: List[List[V]] = []
    # The last key of each chunk, so a search can choose a chunk without reading any. Internal state.
    maxes: List[K] = []
    # Number of entries. Internal state; read it with `length()`.
    size: Int = 0

impl SortedMap[K, V]:
    # Returns the index of the first chunk whose last key is not below `key`, or the last chunk when every key is below it.
    fn chunk_for(key: K) Int:
        var low = 0
        var high = self.maxes.length() - 1

        while low < high:
            let middle = (low + high) / 2

            if order(self.maxes[middle], key) < 0:
                low = middle + 1
            else:
                high = middle

        return low

    # Returns the index of the first key in chunk `c` that is not below `key`, or the chunk length when none.
    fn lower_bound(c: Int, key: K) Int:
        var low = 0
        var high = self.key_chunks[c].length()

        while low < high:
            let middle = (low + high) / 2

            if order(self.key_chunks[c].get(middle), key) < 0:
                low = middle + 1
            else:
                high = middle

        return low

    # Records the last key of chunk `c` after the chunk changed.
    var fn refresh(c: Int) Unit:
        self.maxes.set(c, self.key_chunks[c].get(self.key_chunks[c].length() - 1))

    # Returns the number of entries.
    fn length() Int:
        return self.size

    # Reports whether the map has no entries.
    fn is_empty() Bool:
        return self.size == 0

    # Reports whether an equal key is present.
    fn contains(key: K) Bool:
        if self.size == 0:
            return false

        let c = self.chunk_for(key)
        let at = self.lower_bound(c, key)
        return (
            at < self.key_chunks[c].length()
            and order(self.key_chunks[c].get(at), key) == 0
        )

    # Returns the value stored for an equal key, or none when absent.
    fn get(key: K) Optional[V]:
        if self.size == 0:
            return none

        let c = self.chunk_for(key)
        let at = self.lower_bound(c, key)
        if (
            at < self.key_chunks[c].length()
            and order(self.key_chunks[c].get(at), key) == 0
        ):
            return some(self.value_chunks[c].get(at))

        return none

    # Inserts a key or replaces the value of an equal key, which keeps its original key.
    var fn add(key: K, value: V) Unit:
        if self.size == 0:
            self.key_chunks = [[key]]
            self.value_chunks = [[value]]
            self.maxes = [key]
            self.size = 1
            return

        let c = self.chunk_for(key)
        let at = self.lower_bound(c, key)

        if (
            at < self.key_chunks[c].length()
            and order(self.key_chunks[c].get(at), key) == 0
        ):
            self.value_chunks[c].set(at, value)
            return

        self.key_chunks[c].insert(at, key)
        self.value_chunks[c].insert(at, value)
        self.size += 1
        if at == self.key_chunks[c].length() - 1:
            self.refresh(c)
        if self.key_chunks[c].length() > 256:
            self.split(c)

    # Splits chunk `c` into two halves.
    var fn split(c: Int) Unit:
        let length = self.key_chunks[c].length()
        let half = length / 2
        let tail_keys = self.key_chunks[c].slice(half, length).get()
        let tail_values = self.value_chunks[c].slice(half, length).get()
        self.key_chunks[c].splice(half, length - half, [])
        self.value_chunks[c].splice(half, length - half, [])
        self.key_chunks.insert(c + 1, tail_keys)
        self.value_chunks.insert(c + 1, tail_values)
        self.maxes.insert(c, self.key_chunks[c].get(half - 1))

    # Removes an equal key; an absent key changes nothing.
    var fn remove(key: K) Unit:
        if self.size == 0:
            return

        let c = self.chunk_for(key)
        let at = self.lower_bound(c, key)
        if (
            at >= self.key_chunks[c].length()
            or order(self.key_chunks[c].get(at), key) != 0
        ):
            return

        self.remove_at(c, at)

    # Removes the entry at chunk `c`, position `at`, dropping the chunk when it empties.
    var fn remove_at(c: Int, at: Int) Unit:
        self.key_chunks[c].remove(at)
        self.value_chunks[c].remove(at)
        self.size -= 1

        if self.key_chunks[c].length() == 0:
            self.key_chunks.remove(c)
            self.value_chunks.remove(c)
            self.maxes.remove(c)
        else if at == self.key_chunks[c].length():
            self.refresh(c)

    # Removes every entry and releases the storage; the map is empty afterwards.
    var fn clear() Unit:
        self.key_chunks = []
        self.value_chunks = []
        self.maxes = []
        self.size = 0

    # Returns the entry with the smallest key, or none when empty.
    fn first() Optional[SortedEntry[K, V]]:
        if self.size == 0:
            return none

        return some(SortedEntry(self.key_chunks[0].get(0), self.value_chunks[0].get(0)))

    # Returns the entry with the largest key, or none when empty.
    fn last() Optional[SortedEntry[K, V]]:
        if self.size == 0:
            return none

        let c = self.key_chunks.length() - 1
        let at = self.key_chunks[c].length() - 1
        return some(
            SortedEntry(
                self.key_chunks[c].get(at), self.value_chunks[c].get(at)
            )
        )

    # Removes and returns the entry with the smallest key, or none when empty.
    var fn pop_first() Optional[SortedEntry[K, V]]:
        let entry = self.first()
        if self.size > 0:
            self.remove_at(0, 0)
        return entry

    # Removes and returns the entry with the largest key, or none when empty.
    var fn pop_last() Optional[SortedEntry[K, V]]:
        let entry = self.last()

        if self.size > 0:
            let c = self.key_chunks.length() - 1
            self.remove_at(c, self.key_chunks[c].length() - 1)

        return entry

    # Returns the entry with the smallest key that is at least `key`, or none.
    fn ceiling(key: K) Optional[SortedEntry[K, V]]:
        if self.size == 0:
            return none

        let c = self.chunk_for(key)
        let at = self.lower_bound(c, key)
        if at >= self.key_chunks[c].length():
            return none

        return some(
            SortedEntry(
                self.key_chunks[c].get(at), self.value_chunks[c].get(at)
            )
        )

    # Returns the entry with the largest key that is at most `key`, or none.
    fn floor(key: K) Optional[SortedEntry[K, V]]:
        if self.size == 0:
            return none

        var c = self.chunk_for(key)
        var at = self.lower_bound(c, key)
        if (
            at < self.key_chunks[c].length()
            and order(self.key_chunks[c].get(at), key) == 0
        ):
            return some(
                SortedEntry(
                    self.key_chunks[c].get(at), self.value_chunks[c].get(at)
                )
            )

        if at == 0:
            if c == 0:
                return none

            c -= 1
            at = self.key_chunks[c].length()

        at -= 1
        return some(
            SortedEntry(
                self.key_chunks[c].get(at), self.value_chunks[c].get(at)
            )
        )

    # Returns a new list of the entries with `low` <= key < `high`, in ascending order.
    fn range(low: K, high: K) List[SortedEntry[K, V]]:
        var out: List[SortedEntry[K, V]] = []
        if self.size == 0:
            return out

        var c = self.chunk_for(low)
        var at = self.lower_bound(c, low)

        while c < self.key_chunks.length():
            let keys = self.key_chunks[c]

            while at < keys.length():
                if order(keys.get(at), high) >= 0:
                    return out

                out.append(SortedEntry(keys.get(at), self.value_chunks[c].get(at)))
                at += 1

            c += 1
            at = 0

        return out

    # Returns a new list of the keys in ascending order.
    fn keys() List[K]:
        var out: List[K] = []
        for chunk in self.key_chunks:
            out = out.concat(chunk)
        return out

    # Returns a new list of the values in ascending key order.
    fn values() List[V]:
        var out: List[V] = []
        for chunk in self.value_chunks:
            out = out.concat(chunk)
        return out

    # Returns a new list of the entries in ascending key order.
    fn entries() List[SortedEntry[K, V]]:
        var out: List[SortedEntry[K, V]] = []

        for c in range(0, self.key_chunks.length()):
            let keys = self.key_chunks[c]
            for at in range(0, keys.length()):
                out.append(SortedEntry(keys.get(at), self.value_chunks[c].get(at)))

        return out

    # Calls operation(key:, value:) in ascending key order over a snapshot of the entries.
    fn for_each(operation: fn(key: K, value: V) Unit) Unit:
        for entry in self.entries():
            operation(entry.key, entry.value)

# A set kept in ascending order, with the same Comparable ordering and costs as SortedMap.
# Members that compare equal are the same member. Use clone() for an independent deep copy.
export type SortedSet[T: Comparable]:
    # Members as the keys of a map. Internal state: use the operations, not this field.
    members: SortedMap[T, Bool] = SortedMap[T, Bool]()

impl SortedSet[T]:
    # Returns the number of members.
    fn length() Int:
        return self.members.length()

    # Reports whether the set has no members.
    fn is_empty() Bool:
        return self.members.is_empty()

    # Reports whether an equal member is present.
    fn contains(value: T) Bool:
        return self.members.contains(value)

    # Adds a member; an equal member already present is kept.
    var fn add(value: T) Unit:
        if not self.members.contains(value):
            self.members.add(value, true)

    # Removes an equal member; an absent value changes nothing.
    var fn remove(value: T) Unit:
        self.members.remove(value)

    # Removes every member and releases the storage; the set is empty afterwards.
    var fn clear() Unit:
        self.members.clear()

    # Returns the smallest member, or none when empty.
    fn first() Optional[T]:
        if let entry = self.members.first():
            return some(entry.key)

        return none

    # Returns the largest member, or none when empty.
    fn last() Optional[T]:
        if let entry = self.members.last():
            return some(entry.key)

        return none

    # Removes and returns the smallest member, or none when empty.
    var fn pop_first() Optional[T]:
        if let entry = self.members.pop_first():
            return some(entry.key)

        return none

    # Removes and returns the largest member, or none when empty.
    var fn pop_last() Optional[T]:
        if let entry = self.members.pop_last():
            return some(entry.key)

        return none

    # Returns the smallest member that is at least `value`, or none.
    fn ceiling(value: T) Optional[T]:
        if let entry = self.members.ceiling(value):
            return some(entry.key)

        return none

    # Returns the largest member that is at most `value`, or none.
    fn floor(value: T) Optional[T]:
        if let entry = self.members.floor(value):
            return some(entry.key)

        return none

    # Returns a new list of the members with `low` <= member < `high`, in ascending order.
    fn range(low: T, high: T) List[T]:
        var out: List[T] = []
        for entry in self.members.range(low, high):
            out.append(entry.key)
        return out

    # Returns a new list of the members in ascending order.
    fn values() List[T]:
        return self.members.keys()
