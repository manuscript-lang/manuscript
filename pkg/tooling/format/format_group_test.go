package format

import "testing"

func TestFormatKeepsBindingGroupsTogether(t *testing.T) {
	source := `fn helper() Int: 1
let (
    A = 1
    B: Int   = A+1
)
fn main() Unit:
    let x = 1
    var (
        a = 10
        b = fn(x: Int) Int:
            return x + 1
    )
    let (
        c=11
        d = "Hi"
    )
    a += x + b(c)
`
	want := `fn helper() Int: 1

let (
    A = 1
    B: Int = A + 1
)

fn main() Unit:
    let x = 1
    var (
        a = 10
        b = fn(x: Int) Int:
            return x + 1
    )
    let (
        c = 11
        d = "Hi"
    )
    a += x + b(c)
`
	got, err := Format("group.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
	again, err := Format("group.ms", got)
	if err != nil || again != got {
		t.Fatalf("not idempotent: %v\n%s", err, again)
	}
}
