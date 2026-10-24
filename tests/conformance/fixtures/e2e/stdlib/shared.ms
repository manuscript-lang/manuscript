# conform: tags=records,interfaces,mutation,stdlib-shared,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import {share, Shared} from "@std/shared.ms"
import {expect_equal} from "@std/testing.ms"

type Config:
    name: String
    tags: List[String]

interface Speaker:
    fn say() String

type Dog:
    name: String

impl Speaker for Dog:
    fn say() String:
        return self.name + " says woof"

type Holder:
    config: Shared[Config]
    speaker: Shared[Speaker]

fn make(name: String) Holder:
    let config = share(
        Config(name.clone(), ["a-tag-long-enough-for-the-heap", "second"])
    )
    let speaker = share(Speaker(Dog(name)))
    return Holder(config, speaker)

fn child(holder: Holder) Holder:
    return Holder(holder.config, holder.speaker)

test "copies of a shared value read the same payload":
    let first = make("a-name-long-enough-for-the-heap")
    let second = child(first)
    let third = child(second)
    try expect_equal(third.config.get().name, "a-name-long-enough-for-the-heap")
    try expect_equal(first.config.get().tags[0], "a-tag-long-enough-for-the-heap")
    try expect_equal(
        third.speaker.get().say(), "a-name-long-enough-for-the-heap says woof"
    )

test "the payload outlives the original holder":
    let kept = child(make("x-name-long-enough-for-the-heap-too"))
    try expect_equal(kept.config.get().tags.length(), 2)
