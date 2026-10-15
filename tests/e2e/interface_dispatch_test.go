package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestInterfaceDispatchCoversStructsAlternativesAndScalars(t *testing.T) {
	result := compiler.CompileSource("interface-dispatch.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

interface Named:
    fn label(prefix: String, n: Int) -> String
    fn ratio(by: Float) -> Float
    fn find(key: Int) -> Optional[Int]

type Dog:
    age: Int

type Cat:
    lives: Int

type Mood:
    case Happy
    case Grumpy(level: Int)

impl Named for Dog:
    fn label(prefix: String, n: Int) -> String: "{prefix}dog{self.age + n}"
    fn ratio(by: Float) -> Float: by * 2.0
    fn find(key: Int) -> Optional[Int]:
        if key == self.age:
            return some(key)
        return none

impl Named for Cat:
    fn label(prefix: String, n: Int) -> String: "{prefix}cat{self.lives * n}"
    fn ratio(by: Float) -> Float: by / 2.0
    fn find(key: Int) -> Optional[Int]: none

impl Named for Mood:
    fn label(prefix: String, n: Int) -> String:
        match self:
            Happy:
                return "{prefix}happy"
            Grumpy(level):
                return "{prefix}grumpy{level + n}"
    fn ratio(by: Float) -> Float: by
    fn find(key: Int) -> Optional[Int]: some(key + 1)

fn describe(item: Named, n: Int) -> String: item.label(prefix: "-", n: n)

fn scale(item: Named, by: Float) -> Float: item.ratio(by: by)

fn lookup(item: Named, key: Int) -> Int:
    match item.find(key: key):
        some(v):
            return v
        none:
            return -1

test "dispatch":
    let all: List[Named] = [Named(value: Dog(age: 3)), Named(value: Cat(lives: 9)), Named(value: Mood.Happy), Named(value: Mood.Grumpy(level: 4))]
    var labels = ""
    for item in all:
        labels = labels + describe(item: item, n: 2) + ","
    check(ok: labels == "-dog5,-cat18,-happy,-grumpy6,", name: labels)
    check(ok: scale(item: all.at(index: 0).unwrap(), by: 3.0) == 6.0, name: "dog ratio")
    check(ok: scale(item: all.at(index: 1).unwrap(), by: 3.0) == 1.5, name: "cat ratio")
    check(ok: lookup(item: all.at(index: 0).unwrap(), key: 3) == 3, name: "dog found")
    check(ok: lookup(item: all.at(index: 0).unwrap(), key: 4) == -1, name: "dog missing")
    check(ok: lookup(item: all.at(index: 2).unwrap(), key: 4) == 5, name: "alternative receiver")
`, compiler.Options{Tests: true})
	if !strings.Contains(result.Source, "rt.CallInterface(") || strings.Count(result.Source, "func dispatch") != 3 {
		t.Fatalf("expected one dispatcher for each interface method:\n%s", result.Source)
	}
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("interface dispatch changed: %v\n%s", err, output)
	}
}
