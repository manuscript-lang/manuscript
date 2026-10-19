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

func TestFormatVarMarkers(t *testing.T) {
	source := "impl Box:\n    var fn push(var items:List[Int]) Unit:\n        self.items.append(1)\n\nfn run(var xs: List[Int]) Unit:\n    run(var   xs)\n"
	want := "impl Box:\n    var fn push(var items: List[Int]) Unit:\n        self.items.append(1)\n\nfn run(var xs: List[Int]) Unit:\n    run(var xs)\n"
	got, err := Format("var.ms", source)
	if err != nil || got != want {
		t.Fatalf("err %v\ngot:\n%s\nwant:\n%s", err, got, want)
	}
}
