import {
    Entropy,
    Random,
    RandomError,
    secure_int,
    secure_float,
    secure_choice,
    secure_shuffle,
    seeded
} from "@std/random.ms"
import Bytes from "@std/bytes.ms"
import filled from "@std/collections.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

type ConstantEntropy:
    byte: Int
    calls: Int
    requested: Int

impl Entropy for ConstantEntropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]:
        self.calls = self.calls + 1
        self.requested = count
        return ok(
            Bytes(
                value(filled(self.byte, count))
            )
        )

type BadEntropy:
    calls: Int
    fail: Bool

impl Entropy for BadEntropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]:
        self.calls = self.calls + 1
        if self.fail: return error(RandomError.Failed("original source failure"))

        return ok(Bytes([]))

type Item:
    count: Int

fn pick[T](random: Random, values: List[T]) -> Optional[T]:
    return random.choice[T](values)

fn permute[T](random: Random, values: List[T]) -> List[T]:
    return random.shuffle[T](values)

test "secure float uses 53 bits and secure generic calls retain types":
    let zero = ConstantEntropy(0, 0, 0)
    let high = ConstantEntropy(255, 0, 0)
    if value(
        secure_float(Entropy(zero))
    ) != 0.0: return panic("zero float")
    if zero.requested != 8: return panic("float entropy count")
    if value(
        secure_float(Entropy(high))
    ) != 0.9999999999999999: return panic(
        "float excluded endpoint"
    )
    if value(
        secure_choice(
            Entropy(zero),
            ["first", "second"]
        )
    ) != some(
        "first"
    ): return panic("generic secure choice")

    let choose = secure_choice[String]
    if value(
        choose(
            Entropy(zero),
            ["typed"]
        )
    ) != some("typed"): return panic(
        "specialized secure choice"
    )

    let shuffle = secure_shuffle[Int]
    if value(
        shuffle(
            Entropy(zero),
            [1, 2, 3]
        )
    ) != [2, 3, 1]: return panic(
        "secure Fisher-Yates"
    )
    if value(
        secure_int(
            Entropy(zero),
            -5,
            -2
        )
    ) != -5: return panic(
        "signed optional random bound"
    )

test "secure entropy errors and malformed byte counts return domain errors":
    let failed = BadEntropy(0, true)
    let expected: Result[Float, RandomError] = error(
        RandomError.Failed("original source failure")
    )
    if secure_float(Entropy(failed)) != expected: return panic("float source error")

    let choice_expected: Result[Optional[String], RandomError] = error(
        RandomError.Failed("original source failure")
    )
    if secure_choice(
        Entropy(failed),
        ["value"]
    ) != choice_expected: return panic(
        "choice source error"
    )

    let shuffle_expected: Result[List[Int], RandomError] = error(
        RandomError.Failed("original source failure")
    )
    if secure_shuffle(
        Entropy(failed),
        [1, 2]
    ) != shuffle_expected: return panic(
        "shuffle source error"
    )

    let short = BadEntropy(0, false)
    if not secure_float(Entropy(short)).is_error(): return panic("short float data")
    if not secure_choice(
        Entropy(short),
        [1, 2]
    ).is_error(): return panic(
        "short choice data"
    )
    if not secure_shuffle(
        Entropy(short),
        [1, 2]
    ).is_error(): return panic(
        "short shuffle data"
    )

    let empty: List[String] = []
    let calls = failed.calls
    if not value(
        secure_choice(
            Entropy(failed),
            empty
        )
    ).is_none(): return panic(
        "empty secure choice"
    )
    if value(
        secure_shuffle(
            Entropy(failed),
            empty
        )
    ) != empty: return panic(
        "empty secure shuffle"
    )
    if value(
        secure_shuffle(
            Entropy(failed),
            [1]
        )
    ) != [1]: return panic(
        "singleton secure shuffle"
    )
    if failed.calls != calls: return panic("trivial secure operations read entropy")

test "seeded SplitMix64 has stable vectors and signed unbiased integer ranges":
    let random = seeded(0)
    if random.float() != 0.8833108082136426: return panic("first SplitMix64 float")
    if random.float() != 0.43152799704850997: return panic("second SplitMix64 float")
    if random.float() != 0.026433771592597743: return panic("third SplitMix64 float")

    let ints = seeded(0)
    if value(ints.int(0, 100)) != 35: return panic("first bounded integer")
    if value(ints.int(0, 100)) != 0: return panic("second bounded integer")
    if value(ints.int(0, 100)) != 79: return panic("third bounded integer")
    if value(seeded(3).int(-9223372036854775808, 1)) != -5528608851982440056: return panic(
        "wide integer range rejection"
    )
    if value(seeded(-1).int(-9, -2)) >= -2: return panic("negative upper bound")

    let invalid: Result[Int, RandomError] = error(RandomError.InvalidInput)
    if ints.int(2, 2) != invalid: return panic("empty integer range")
    if ints.int(3, 2) != invalid: return panic("reversed integer range")

    let defaults = seeded(9)
    let explicit = seeded(9)
    if defaults.int(-5) != explicit.int(-5, none): return panic(
        "optional bound default"
    )

    let bound = seeded(0).int
    if value(bound(0, 100)) != 35: return panic("bound generator method")

    let state = seeded(0)
    let alias = state
    if alias.float() != 0.8833108082136426: return panic("aliased first draw")
    if state.float() != 0.43152799704850997: return panic("aliased state advanced")

test "seeded generic choice and shuffle are reproducible fresh shallow lists":
    let first = seeded(42)
    let second = seeded(42)
    let choices = ["a", "b", "c"]
    if pick(first, choices) != pick(second, choices): return panic("generic choice")

    let choose = first.choice[String]
    let choose_again = second.choice[String]
    if choose(choices) != choose_again(choices): return panic("bound generic choice")

    let empty: List[Int] = []
    let unchanged = seeded(0)
    if not unchanged.choice(empty).is_none(): return panic("empty seeded choice")
    if unchanged.shuffle(empty) != empty: return panic("empty seeded shuffle")
    if unchanged.shuffle([1]) != [1]: return panic("singleton seeded shuffle")
    if unchanged.float() != seeded(0).float(): return panic(
        "trivial operation advanced state"
    )

    let original = [1, 2, 3, 4]
    let shuffled = permute(
        seeded(42),
        original
    )
    let shuffle = seeded(42).shuffle[Int]
    if shuffled != shuffle(original): return panic("stable generic Fisher-Yates")

    shuffled.set(0, 99)
    if original != [1, 2, 3, 4]: return panic("seeded shuffle changed input storage")

    let item = Item(1)
    let objects = [item]
    let copied = seeded(1).shuffle(objects)
    let copied_item = copied.at(0).unwrap()
    copied_item.count = 5
    if item.count != 5: return panic("shuffle deep copied elements")

    copied.set(
        0,
        Item(9)
    )
    if objects.at(0).unwrap().count != 5: return panic("shuffle shared outer storage")

    let secure = value(
        secure_shuffle(
            Entropy(ConstantEntropy(0, 0, 0)),
            objects
        )
    )
    let secure_item = secure.at(0).unwrap()
    secure_item.count = 7
    if item.count != 7: return panic("secure shuffle deep copied elements")

    secure.set(
        0,
        Item(10)
    )
    if objects.at(0).unwrap().count != 7: return panic(
        "secure shuffle shared outer storage"
    )
