import panic from "@std/core.ms"
import StringBuilder from "@std/string.ms"

/*
Compare text by edit distance, similarity, closest candidate, or a unified line diff.
Strings are compared by Unicode scalar, lines by exact equality.
`diff.edit_distance("kitten", "sitting")` is `3`.
*/

// Returns the number of single-scalar insertions, deletions and substitutions that turn `left` into `right` (Levenshtein distance).
// Example: `edit_distance("kitten", "sitting")` is `3`; equal strings give 0.
export fn edit_distance(left: String, right: String) Int:
    if left == right: return 0

    let a = left.chars()
    let b = right.chars()
    var previous: List[Int] = []
    for j in 0..b.length() + 1:
        previous.append(j)

    for i in 1..a.length() + 1:
        var current: List[Int] = [i]

        for j in 1..b.length() + 1:
            let cost = if a[i - 1] == b[j - 1]: 0 else: 1
            current.append(
                (previous[j] + 1).min(
                    (current[j - 1] + 1).min(previous[j - 1] + cost)
                )
            )

        previous = current

    return previous[b.length()]

// Returns the length of the longest common subsequence of two lists of text.
fn common_length(a: List[String], b: List[String]) Int:
    var previous = [0].repeated(b.length() + 1)

    for i in 1..a.length() + 1:
        var current: List[Int] = [0]

        for j in 1..b.length() + 1:
            if a[i - 1] == b[j - 1]:
                current.append(previous[j - 1] + 1)
            else:
                current.append(previous[j].max(current[j - 1]))

        previous = current

    return previous[b.length()]

/*
Returns how alike two strings are, from 0.0 (nothing shared) to 1.0 (equal): twice the length of their longest common subsequence of scalars, divided by the total length.
Two empty strings give 1.0. Use `close_matches` to rank a list of candidates by this score.
Example: `similarity_ratio("abcd", "abd")` is about `0.857`.
*/
export fn similarity_ratio(left: String, right: String) Float:
    if left == right: return 1.0

    let a = left.chars()
    let b = right.chars()
    let total = a.length() + b.length()
    if total == 0: return 1.0

    return 2.0 * common_length(a, b).to_float() / total.to_float()

// A candidate string with its similarity to the word searched for.
type Scored:
    text: String
    score: Float

// Settings for `close_matches`.
export type CloseMatchesOptions:
    // Maximum candidates returned; below 1 faults.
    limit: Int = 3
    // Minimum `similarity_ratio` from 0.0 to 1.0; outside that range faults.
    cutoff: Float = 0.6

/*
Returns up to `options.limit` candidates whose `similarity_ratio` with `word` is at least `options.cutoff`, best match first; ties keep the candidates' order.
Example: `close_matches("appel", ["ape", "apple", "peach"], CloseMatchesOptions(limit: 2))` is `["apple", "ape"]`.
*/
export fn close_matches(
    word: String,
    candidates: List[String],
    options: CloseMatchesOptions = CloseMatchesOptions()
) List[String]:
    let limit = options.limit
    let cutoff = options.cutoff
    if limit < 1:
        panic("close_matches: limit must be at least 1")
    if not (cutoff >= 0.0 and cutoff <= 1.0):
        panic("close_matches: cutoff must be from 0.0 to 1.0")

    var scored: List[Scored] = []

    for candidate in candidates:
        let score = similarity_ratio(word, candidate)
        if score >= cutoff:
            scored.append(Scored(text: candidate.clone(), score: score))

    let ranked = scored.sorted(fn a, b: compare_scores(a.score, b.score))
    return ranked.take(limit).map(fn s: s.text.clone())

fn compare_scores(left: Float, right: Float) Int:
    if left > right: return -1
    if left < right: return 1

    return 0

// One step of a line diff: a line kept (0), removed from the old text (1) or added in the new text (2).
type Step:
    kind: Int
    text: String
    // Lines of the old text consumed before this step.
    old_at: Int
    // Lines of the new text consumed before this step.
    new_at: Int

// Walks the longest common subsequence table to list the steps that turn `old` into `new`, deletions before insertions within a change.
fn middle_steps(old: List[String], new: List[String], shift: Int) List[Step]:
    var table = (0..old.length() + 1).map(fn _row: [0].repeated(new.length() + 1))
    var i = old.length() - 1

    while i >= 0:
        var j = new.length() - 1

        while j >= 0:
            if old[i] == new[j]:
                table[i].set(j, table[i + 1][j + 1] + 1)
            else:
                table[i].set(j, table[i + 1][j].max(table[i][j + 1]))

            j -= 1

        i -= 1

    var steps: List[Step] = []
    var a = 0
    var b = 0

    while a < old.length() or b < new.length():
        if a < old.length() and b < new.length() and old[a] == new[b]:
            steps.append(
                Step(
                    kind: 0, text: old[a].clone(), old_at: a + shift, new_at: b + shift
                )
            )
            a += 1
            b += 1
        else if (
            a < old.length()
            and (b == new.length() or table[a + 1][b] >= table[a][b + 1])
        ):
            steps.append(
                Step(
                    kind: 1, text: old[a].clone(), old_at: a + shift, new_at: b + shift
                )
            )
            a += 1
        else:
            steps.append(
                Step(
                    kind: 2, text: new[b].clone(), old_at: a + shift, new_at: b + shift
                )
            )
            b += 1

    return steps

// Formats a hunk range like unified diff: the 1-based start and length, with an empty range counted from the line before it.
// Matches common leading and trailing lines directly, so only the differing middle pays for the quadratic table.
fn line_steps(old: List[String], new: List[String]) List[Step]:
    var head = 0
    while head < old.length() and head < new.length() and old[head] == new[head]:
        head += 1

    var tail = 0
    while (
        tail < old.length() - head
        and tail < new.length() - head
        and old[old.length() - 1 - tail] == new[new.length() - 1 - tail]
    ):
        tail += 1

    var steps: List[Step] = []
    for i in 0..head:
        steps.append(Step(kind: 0, text: old[i].clone(), old_at: i, new_at: i))

    var old_middle: List[String] = []
    var new_middle: List[String] = []
    for i in head..old.length() - tail:
        old_middle.append(old[i].clone())
    for i in head..new.length() - tail:
        new_middle.append(new[i].clone())
    steps.extend(middle_steps(old_middle, new_middle, head))

    for i in 0..tail:
        let at = old.length() - tail + i
        let other = new.length() - tail + i
        steps.append(Step(kind: 0, text: old[at].clone(), old_at: at, new_at: other))

    return steps

fn hunk_range(start: Int, length: Int) String:
    if length == 1: return "{start + 1}"
    if length == 0: return "{start},0"

    return "{start + 1},{length}"

// Settings for `unified_diff`.
export type UnifiedDiffOptions:
    // Unchanged lines kept around each change; must not be negative.
    context: Int = 3
    // Label of the `---` header.
    old_name: String = "a"
    // Label of the `+++` header.
    new_name: String = "b"

/*
Compares two lists of lines and returns the differences in unified diff format, or an empty string when the lists are equal.
Lines carry no trailing newline, and the result lines are joined with "\n" with a final newline.
Example: `unified_diff(["a", "b"], ["a", "c"], UnifiedDiffOptions(context: 1))` is `"--- a\n+++ b\n@@ -1,2 +1,2 @@\n a\n-b\n+c\n"`.
*/
export fn unified_diff(
    old: List[String],
    new: List[String],
    options: UnifiedDiffOptions = UnifiedDiffOptions()
) String:
    let context = options.context
    let old_name = options.old_name
    let new_name = options.new_name
    if context < 0:
        panic("unified_diff: context must not be negative")

    let steps = line_steps(old, new)
    var keep = [false].repeated(steps.length())
    var any_change = false

    for i in 0..steps.length():
        if steps[i].kind != 0:
            any_change = true

            let from = (i - context).max(0)
            let to = i + context.min(steps.length() - 1 - i)

            // Windows move right: the first marked position joins the prior window.
            var j = to

            while j >= from and not keep[j]:
                keep.set(j, true)
                j -= 1

    if not any_change: return ""

    var out = StringBuilder()
    out.append("--- {old_name}\n+++ {new_name}\n")

    var i = 0

    while i < steps.length():
        if not keep[i]:
            i += 1
            continue

        var end = i
        while end < steps.length() and keep[end]:
            end += 1

        var old_length = 0
        var new_length = 0

        for j in i..end:
            if steps[j].kind != 2:
                old_length += 1
            if steps[j].kind != 1:
                new_length += 1

        out.append(
            "@@ -{hunk_range(steps[i].old_at, old_length)} +{hunk_range(steps[i].new_at, new_length)} @@\n"
        )

        for j in i..end:
            var mark = " "

            if steps[j].kind == 1:
                mark = "-"
            else if steps[j].kind == 2:
                mark = "+"

            out.append("{mark}{steps[j].text}\n")

        i = end

    return out.build()
