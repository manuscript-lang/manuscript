package format

import "testing"

func TestFormatPipeFlow(t *testing.T) {
	source := "fn double(n: Int) Int: n * 2\n\nfn run(n: Int) Int:\n    let a = n|double|double\n    let b = n\n        |double   # first\n        # second\n        |double\n    return a+b\n"
	want := "fn double(n: Int) Int: n * 2\n\nfn run(n: Int) Int:\n    let a = n | double | double\n    let b = n\n        | double  # first\n        # second\n        | double\n    return a + b\n"
	got, err := Format("pipe.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
	again, err := Format("pipe.ms", got)
	if err != nil || again != got {
		t.Fatalf("not idempotent: %v\n%s", err, again)
	}
}

func TestFormatPipeDotStep(t *testing.T) {
	source := "fn run(n: Int) Int:\n    let a = n |.size()|try.m()| .k\n    return a\n"
	want := "fn run(n: Int) Int:\n    let a = n | .size() | try .m() | .k\n    return a\n"
	got, err := Format("pipe.ms", source)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
}
