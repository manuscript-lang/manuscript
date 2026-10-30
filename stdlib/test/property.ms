import Pair from "@std/collections.ms"
import panic from "@std/core.ms"
import stderr from "@std/io.ms"
import bit_xor, shift_right_unsigned, wrapping_add, wrapping_multiply, max_int from "@std/math.ms"
import control from "@std/process.ms"
import entropy, secure_int from "@std/random.ms"
import expect_fault, fail from "@std/test.ms"
import clock, milliseconds from "@std/time.ms"

# Property-based testing for `test` blocks. A property is a function that must hold for every value a generator produces.
# `check` runs it on many generated values and, on failure, shrinks the input to a small counterexample.
# Generators draw integers from a `Source` that records them, so a failing input shrinks by editing the recorded
# draws (deleting spans, lowering values) and replaying the generator. Every generator, including your own
# composed with `map`, `flat_map`, `lists`, and the rest, therefore shrinks without a shrinker of its own.
# Example: `try check("reverse twice", lists(ints(-100, 100)), lambda xs: expect_equal(xs.reversed().reversed(), xs))`.
# `ms test --runs N`, `--seed N`, and `--fuzz DURATION` set the case count, the starting seed, and a time budget.

# The recorded stream of draws a generator reads. Create one with `source`; generators call `draw`.
export type Source:
    # Every draw so far, in order, each within its bound.
    choices: List[Int]
    # How many entries of `choices` the current generation has read.
    pos: Int
    # Pseudo-random state; fresh draws past the recorded prefix come from it.
    state: Int
    # True while generating new input, false while replaying a recorded prefix (missing draws read as 0).
    fresh: Bool
    # Set by `filter` when it cannot satisfy its predicate; `check` discards such cases instead of running them.
    invalid: Bool

# Returns a source that generates fresh input from `seed`.
export fn source(seed: Int) Source:
    return Source([], 0, seed, true, false)

# A generated value and the source after the draws that made it.
export type Drawn[T]:
    # The value a generator built from the draws it read.
    value: T
    # The source to continue drawing from; draws already made are recorded in it.
    source: Source

impl Source:
    # Returns the next 64 random bits as a signed Int (SplitMix64).
    var fn next_bits() Int:
        self.state = wrapping_add(self.state, -7046029254386353131)

        var z = self.state
        z = wrapping_multiply(
            bit_xor(z, shift_right_unsigned(z, 30)), -4658895280553007687
        )
        z = wrapping_multiply(
            bit_xor(z, shift_right_unsigned(z, 27)), -7723592293110705685
        )
        return bit_xor(z, shift_right_unsigned(z, 31))

# Draws an integer from 0 through `max`, both included, and returns it with the advanced source; `max` must not be negative.
# Fresh draws favor the two ends. Shrinking lowers each draw toward 0, so 0 is the simplest outcome.
export fn draw(source: Source, max: Int) Drawn[Int]:
    var s = source
    var value = 0

    if s.pos < s.choices.length():
        value = s.choices[s.pos]
        if value > max:
            value = max
        s.choices[s.pos] = value
    else if s.fresh:
        let bits = s.next_bits()
        let positive = shift_right_unsigned(bits, 1)
        let edge = shift_right_unsigned(bits, 59) % 16

        if edge == 0:
            value = 0
        else if edge == 1:
            value = max
        else if max == max_int():
            value = positive
        else:
            value = positive % (max + 1)

        s.choices.append(value)
    else:
        s.choices.append(0)

    s.pos += 1
    return Drawn(value, s)

# A generator of `T` values. Build one with the functions below; run it with `check`.
export type Gen[T]:
    # Reads draws from the source and builds a value.
    make: fn(Source) Drawn[T]

# Generates integers from `low` through `high`, both included, shrinking toward the value nearest 0.
# When the range spans 0, a sign draw comes first and the magnitude after it. `high - low` must fit in Int.
export fn ints(low: Int, high: Int) Gen[Int]:
    return Gen[Int](fn s: ints_draw(s, low, high))

fn ints_draw(s: Source, low: Int, high: Int) Drawn[Int]:
    if low >= 0:
        let {value, source} = draw(s, high - low)
        return Drawn(low + value, source)

    if high <= 0:
        let {value, source} = draw(s, high - low)
        return Drawn(high - value, source)

    let {value: sign, source: middle} = draw(s, 1)

    if sign == 0:
        let {value, source} = draw(middle, high)
        return Drawn(value, source)

    let {value, source} = draw(middle, 0 - low)
    return Drawn(0 - value, source)

# Generates `True` and `False`, shrinking toward `False`.
export fn bools() Gen[Bool]:
    return Gen[Bool](fn s: bool_draw(s))

fn bool_draw(s: Source) Drawn[Bool]:
    let {value, source} = draw(s, 1)
    return Drawn(value == 1, source)

# Generates floats from `low` through `high` at 2^-53 resolution, shrinking toward `low`.
export fn floats(low: Float, high: Float) Gen[Float]:
    return Gen[Float](fn s: float_draw(s, low, high))

fn float_draw(s: Source, low: Float, high: Float) Drawn[Float]:
    let {value, source} = draw(s, 9007199254740992)
    return Drawn(low + (high - low) * (value.to_float() / 9007199254740992.0), source)

# Always generates a copy of `value`, consuming no draws, so it never shrinks.
export fn constant[T: Clonable](value: T) Gen[T]:
    return Gen[T](fn s: Drawn(value.clone(), s))

# Generates one of `values`, shrinking toward the first. `values` must not be empty.
export fn element_of[T: Clonable](values: List[T]) Gen[T]:
    return Gen[T](fn s: element_draw(values, s))

fn element_draw[T: Clonable](values: List[T], s: Source) Drawn[T]:
    let {value, source} = draw(s, values.length() - 1)
    return Drawn(values[value].clone(), source)

# Generates by picking one of `gens`, shrinking toward the first. `gens` must not be empty.
export fn one_of[T](gens: List[Gen[T]]) Gen[T]:
    return Gen[T](fn s: one_draw(gens, s))

fn one_draw[T](gens: List[Gen[T]], s: Source) Drawn[T]:
    let {value, source} = draw(s, gens.length() - 1)
    return gens[value].make(source)

impl Gen[T]:
    # Transforms every generated value.
    fn map[B](transform: fn(T) B) Gen[B]:
        return Gen[B](fn s: map_draw(self, transform, s))

    # Generates a value, then generates again with a generator chosen from it (dependent generation).
    fn flat_map[B](next: fn(T) Gen[B]) Gen[B]:
        return Gen[B](fn s: flat_map_draw(self, next, s))

    # Keeps values for which `keep` is true. After 50 consecutive rejections the case is marked invalid and discarded.
    fn filter(keep: fn(T) Bool) Gen[T]:
        return Gen[T](fn s: filter_draw(self, keep, s))

    # Combines one value from this generator with one from `other`.
    fn zip[B, C](other: Gen[B], combine: fn(T, B) C) Gen[C]:
        return Gen[C](fn s: zip_draw(self, other, combine, s))

fn map_draw[A, B](gen: Gen[A], transform: fn(A) B, s: Source) Drawn[B]:
    let {value, source} = gen.make(s)
    return Drawn(transform(value), source)

fn flat_map_draw[A, B](gen: Gen[A], next: fn(A) Gen[B], s: Source) Drawn[B]:
    let {value, source} = gen.make(s)
    return next(value).make(source)

fn filter_draw[T](gen: Gen[T], keep: fn(T) Bool, s: Source) Drawn[T]:
    var cursor = s
    var tries = 0

    while true:
        let {value, source} = gen.make(cursor)
        tries += 1
        if keep(value):
            return Drawn(value, source)

        if tries >= 50:
            var rejected = source
            rejected.invalid = true
            return Drawn(value, rejected)

        cursor = source

fn zip_draw[A, B, C](
    first: Gen[A],
    second: Gen[B],
    combine: fn(A, B) C,
    s: Source
) Drawn[C]:
    let {value: a, source: middle} = first.make(s)
    let {value: b, source} = second.make(middle)
    return Drawn(combine(a, b), source)

# Generates `some(value)` or `none`, shrinking toward `none`.
export fn optionals[T](gen: Gen[T]) Gen[Optional[T]]:
    return Gen[Optional[T]](fn s: optional_draw(gen, s))

fn optional_draw[T](gen: Gen[T], s: Source) Drawn[Optional[T]]:
    let {value: flag, source: middle} = draw(s, 3)
    if flag == 0:
        return Drawn(none, middle)

    let {value, source} = gen.make(middle)
    return Drawn(value, source)

# Generates lists of `min_length` through `max_length` elements, shrinking toward fewer and simpler elements.
export fn lists[T](gen: Gen[T], min_length: Int = 0, max_length: Int = 20) Gen[List[T]]:
    return Gen[List[T]](fn s: list_draw(gen, min_length, max_length, s))

fn list_draw[T](gen: Gen[T], min_length: Int, max_length: Int, s: Source) Drawn[List[T]]:
    var items = List[T]()
    var cursor = s

    while items.length() < min_length:
        let {value, source} = gen.make(cursor)
        items.append(value)
        cursor = source

    # Each further element is preceded by a continue flag so that deleting an element's draws removes the element.
    while items.length() < max_length:
        let {value: flag, source: middle} = draw(cursor, 3)

        if flag == 0:
            cursor = middle
            break

        let {value, source} = gen.make(middle)
        items.append(value)
        cursor = source

    return Drawn(items, cursor)

# Generates strings of up to `max_length` characters drawn from `alphabet`, shrinking toward shorter text of its first characters.
# `alphabet` must not be empty.
export fn strings(
    alphabet: String = "abcdefghijklmnopqrstuvwxyz0123456789 ",
    max_length: Int = 20
) Gen[String]:
    var letters = List[String]()
    for c in alphabet.chars():
        letters.append(c)
    return lists(element_of(letters), 0, max_length).map(fn cs: cs.join(""))

# Generates a 2-element `Pair`.
export fn pairs[A, B](first: Gen[A], second: Gen[B]) Gen[Pair[A, B]]:
    return first.zip(second, fn a, b: Pair(a, b))

# Run settings. `ms test` fills them from `--runs`, `--seed`, and `--fuzz` through environment variables.
export type Settings:
    # Cases to run when not fuzzing.
    runs: Int
    # First case seed, or none for a random one that failures report.
    seed: Optional[Int]
    # Time budget in milliseconds; above 0, cases run until it expires instead of stopping at `runs`.
    fuzz_milliseconds: Int

# Returns defaults with `ms test` flag overrides (`MS_TEST_RUNS`, `MS_TEST_SEED`, `MS_TEST_FUZZ_MS`) applied.
export fn settings(runs: Int = 100) Settings:
    var found = Settings(runs, none, 0)
    let environment = control().environment().get(Map[String, String]())
    if let text = environment.get("MS_TEST_RUNS"):
        found.runs = text.parse_int().get(runs)
    if let text = environment.get("MS_TEST_SEED"):
        found.seed = text.parse_int()
    if let text = environment.get("MS_TEST_FUZZ_MS"):
        found.fuzz_milliseconds = text.parse_int().get(0)
    return found

# Result of running one case: the replayed source, and the failure when the property did not hold.
type Outcome:
    source: Source
    failure: Optional[String]

fn run_case[T](gen: Gen[T], property: fn(T) Result[Unit, Error], s: Source) Outcome:
    let {value, source} = gen.make(s)
    if source.invalid:
        return Outcome(source, none)

    # The property runs under `expect_fault` so a fault becomes a failing case that shrinks like an error.
    # It faults with `property_failed` when the property returns an error; that message is then read in full by rerunning
    # on a regenerated value, because the faulted run may have consumed `value` (Windows runs it in this process).
    let faulted = expect_fault(fn: run_property(property, value))
    if faulted.is_error():
        return Outcome(source, none)

    let message = faulted.get("")
    if message != property_failed:
        return Outcome(source, "fault: {message}")

    let replayed = Source(source.choices.take(source.pos), 0, 0, false, false)
    let {value: again} = gen.make(replayed)
    let outcome = property(again)
    return Outcome(source, outcome.err().message())

let property_failed = "property returned an error"

fn run_property[T](property: fn(T) Result[Unit, Error], value: T) Unit:
    if property(value).is_error():
        panic(property_failed)

# Order used to guarantee shrinking terminates: fewer draws first, then lexicographically smaller.
fn simpler(candidate: List[Int], current: List[Int]) Bool:
    if candidate.length() != current.length():
        return candidate.length() < current.length()

    for i in 0..candidate.length():
        if candidate[i] != current[i]:
            return candidate[i] < current[i]
    return false

fn replay[T](
    gen: Gen[T],
    property: fn(T) Result[Unit, Error],
    choices: List[Int]
) Outcome:
    return run_case(gen, property, Source(choices.clone(), 0, 0, false, false))

# Tries `candidate`; returns the used draws when it still fails and is simpler than `current`.
fn attempt[T](
    gen: Gen[T],
    property: fn(T) Result[Unit, Error],
    candidate: List[Int],
    current: List[Int]
) Optional[List[Int]]:
    let outcome = replay(gen, property, candidate)
    if outcome.failure.is_none():
        return none

    let used = outcome.source.choices.take(outcome.source.pos)
    if not simpler(used, current):
        return none

    return used

# Shrinks failing `choices`: deletes spans, then lowers values, until a full pass makes no progress or `budget` replays run.
fn shrink[T](
    gen: Gen[T],
    property: fn(T) Result[Unit, Error],
    choices: List[Int],
    budget: Int
) List[Int]:
    var best = choices.clone()
    var spent = 0
    var progress = true

    while progress and spent < budget:
        progress = false

        for size in [8, 4, 2, 1]:
            var start = best.length() - size

            while start >= 0 and spent < budget:
                let candidate = best.take(start).concat(best.drop(start + size))
                spent += 1

                if let used = attempt(gen, property, candidate, best):
                    best = used
                    progress = true

                start -= 1

        var index = 0

        while index < best.length() and spent < budget:
            let current = best[index]

            for target in [0, current / 2, current - 1]:
                if target >= 0 and target < best[index] and spent < budget:
                    var candidate = best.clone()
                    candidate[index] = target
                    spent += 1

                    if let used = attempt(gen, property, candidate, best):
                        best = used
                        progress = true

            index += 1

    return best

# Runs `property` on generated values and fails, naming a shrunk counterexample, when it returns an error.
# Properties return `Result` like test assertions; write them with `expect_*` calls and `try`.
# A fault (`panic`) inside a property counts as a failing case and shrinks like an error; each case runs under `expect_fault`.
export fn check[T](
    name: String,
    gen: Gen[T],
    property: fn(T) Result[Unit, Error],
    runs: Int = 100,
    seed: Optional[Int] = none
) Result[Unit, Error]:
    let config = settings(runs)
    var chosen = seed
    if chosen.is_none():
        chosen = config.seed

    var base = 0

    if let given = chosen:
        base = given
    else:
        base = try secure_int(entropy(), 0, max_int())

    let fuzzing = config.fuzz_milliseconds > 0
    if fuzzing:
        # Printed first so an interrupted run can still be replayed.
        (
            stderr()
            .write(
                "fuzzing property '{name}' from seed {base} (rerun with --seed {base})\n"
            )
            .get()
        )

    let clk = clock()
    let deadline = clk.now().shift(milliseconds(config.fuzz_milliseconds))
    var case_index = 0
    var executed = 0
    var discarded = 0

    while (
        (fuzzing and clk.now().compare(deadline) < 0)
        or (not fuzzing and executed < config.runs)
    ):
        let case_seed = wrapping_add(base, case_index)
        case_index += 1

        let outcome = run_case(gen, property, source(case_seed))

        if outcome.source.invalid:
            discarded += 1
            if discarded > 10 * config.runs + 1000:
                return fail(
                    "property '{name}': {discarded} generated cases were discarded by filter; loosen the filter"
                )

            continue

        executed += 1
        if let message = outcome.failure:
            return report(
                name, gen, property, outcome.source, message, case_seed, executed
            )

    return ok(unit)

fn report[T](
    name: String,
    gen: Gen[T],
    property: fn(T) Result[Unit, Error],
    failing: Source,
    message: String,
    seed: Int,
    executed: Int
) Result[Unit, Error]:
    let used = failing.choices.take(failing.pos)
    let small = shrink(gen, property, used, 2000)
    let final = replay(gen, property, small)
    let {value: shown} = gen.make(Source(small.clone(), 0, 0, false, false))
    let reason = final.failure.get(message)
    return fail(
        "property '{name}' failed after {executed} cases (case seed {seed}; rerun with --seed {seed})\ncounterexample: {shown}\n{reason}"
    )
