package msruntime

import (
	"bytes"
	"context"
	"os"
	"strings"
	"testing"
	"time"
)

func libraryPlain(t *testing.T, name string, a ...Value) Value {
	t.Helper()
	spec, ok := libraryFunctions[name]
	if !ok {
		t.Fatal(name)
	}
	return StandardFunction(name, libraryRuntimeType(spec.Result)).(Function).Body(RootExecution(), a)
}

func TestBuildersAppendInLinearTime(t *testing.T) {
	ctx := RootExecution()
	start := time.Now()
	text := newBuilder("@std/StringBuilder")
	data := newBuilder("@std/BytesBuilder")
	const n = 300000
	for i := 0; i < n; i++ {
		text.Operation("append").Body(ctx, []Value{"x"})
		data.Operation("append").Body(ctx, []Value{int64(i % 256)})
		data.Operation("concat").Body(ctx, []Value{Bytes{[]byte("0123456789")}})
	}
	if got := text.Operation("freeze").Body(ctx, nil); got != strings.Repeat("x", n) {
		t.Fatalf("string builder produced %d bytes", len(got.(string)))
	}
	if got := data.Operation("freeze").Body(ctx, nil).(Bytes); len(got.Items) != n*11 || got.Items[11] != 1 || got.Items[12] != '0' {
		t.Fatalf("bytes builder produced %d bytes", len(got.Items))
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("builders are not linear: %v", elapsed)
	}
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("sealed builder accepted append")
			}
		}()
		text.Operation("append").Body(ctx, []Value{"y"})
	}()
}

func TestStringIndexingMatchesScalars(t *testing.T) {
	text := "aé世😀b"
	scalars := []rune(text)
	for i := -7; i <= 7; i++ {
		got := libraryPlain(t, "string/scalar_at", text, int64(i)).(Alternative)
		j := i
		if j < 0 {
			j += len(scalars)
		}
		if j < 0 || j >= len(scalars) {
			if got.Tag != "none" {
				t.Fatalf("at %d: %#v", i, got)
			}
			continue
		}
		if got.Tag != "some" || got.Fields[0] != int64(scalars[j]) {
			t.Fatalf("scalar_at %d: %#v", i, got)
		}
		if s := libraryPlain(t, "string/at", text, int64(i)).(Alternative); s.Fields[0] != string(scalars[j]) {
			t.Fatalf("at %d: %#v", i, s)
		}
	}
	for _, input := range []string{text, "hello"} {
		runes := []rune(input)
		for s := 0; s <= len(runes); s++ {
			for e := s; e <= len(runes); e++ {
				if got := libraryPlain(t, "string/slice", input, int64(s), int64(e)); got != Value(string(runes[s:e])) {
					t.Fatalf("slice %q %d:%d = %#v", input, s, e, got)
				}
			}
		}
	}
}

func TestBytesSliceSharesWithoutAliasingAppends(t *testing.T) {
	data := Bytes{[]byte("abcdef")}
	head := libraryPlain(t, "bytes/slice", data, int64(0), int64(3)).(Bytes)
	builder := newBuilder("@std/BytesBuilder")
	builder.Operation("concat").Body(RootExecution(), []Value{head})
	builder.Operation("append").Body(RootExecution(), []Value{int64('z')})
	if string(data.Items) != "abcdef" || string(head.Items) != "abc" {
		t.Fatalf("slice parent changed: %q %q", data.Items, head.Items)
	}
	if cap(head.Items) != 3 {
		t.Fatalf("slice capacity leaks parent storage: %d", cap(head.Items))
	}
}

func TestReadLineBuffersWithoutLosingBytes(t *testing.T) {
	ctx := RootExecution()
	dir := t.TempDir()
	fs := &libraryFileSystem{dir}
	view := librarySuccess(t, fs.Operation("open").Body(ctx, []Value{"lines", "w+", int64(0600)}))
	h := view.(View).Receiver.(*libraryFileHandle)
	librarySuccess(t, h.Operation("write_file").Body(ctx, []Value{Bytes{[]byte("one\r\ntwo\n\nlast")}}))
	librarySuccess(t, h.Operation("seek").Body(ctx, []Value{int64(0), int64(0)}))
	reader := h.Operation("reader").Body(ctx, nil)
	next := func() Value { return libraryCall(t, "io/read_line", reader, int64(100)).Fields[0] }
	want := []string{"one", "two", ""}
	for _, line := range want {
		if got := next(); !Equal(got, optional("String", line, true)) {
			t.Fatalf("want %q got %#v", line, got)
		}
	}
	rest := librarySuccess(t, Bind(reader, "", "read").(Function).Body(ctx, []Value{optional("Int", int64(100), true)}))
	if !Equal(rest, optional("@std/Bytes", Bytes{[]byte("last")}, true)) {
		t.Fatalf("read after read_line: %#v", rest)
	}
	if got := next(); !Equal(got, optional("String", nil, false)) {
		t.Fatalf("expected end: %#v", got)
	}
	librarySuccess(t, h.Operation("seek").Body(ctx, []Value{int64(0), int64(0)}))
	libraryFailure(t, libraryCall(t, "io/read_line", reader, int64(2)), "LimitExceeded")
}

func TestReadLineOnPipeKeepsReadAhead(t *testing.T) {
	input, output, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	output.WriteString("alpha\nbeta\ngamma")
	output.Close()
	ctx := RootExecution()
	in := ViewOf("@std/ReadStream", &stream{file: input, resultType: "@std/Result[@std/Optional[@std/Bytes]][@std/IoError]"})
	for _, line := range []string{"alpha", "beta", "gamma"} {
		if got := librarySuccess(t, libraryCall(t, "io/read_line", in, int64(100))); !Equal(got, optional("String", line, true)) {
			t.Fatalf("want %q got %#v", line, got)
		}
	}
	if got := librarySuccess(t, libraryCall(t, "io/read_line", in, int64(100))); !Equal(got, optional("String", nil, false)) {
		t.Fatalf("expected end: %#v", got)
	}
	_ = ctx
}

func BenchmarkStringBuilderAppend(b *testing.B) {
	ctx := RootExecution()
	for i := 0; i < b.N; i++ {
		builder := newBuilder("@std/StringBuilder")
		for j := 0; j < 50000; j++ {
			builder.Operation("append").Body(ctx, []Value{"x"})
		}
	}
}

func BenchmarkBytesBuilderConcat(b *testing.B) {
	ctx := RootExecution()
	chunk := Bytes{[]byte("0123456789")}
	for i := 0; i < b.N; i++ {
		builder := newBuilder("@std/BytesBuilder")
		for j := 0; j < 20000; j++ {
			builder.Operation("concat").Body(ctx, []Value{chunk})
		}
	}
}

func BenchmarkStringAt(b *testing.B) {
	text := strings.Repeat("ab", 20000)
	spec := libraryFunctions["string/at"]
	fn := StandardFunction("string/at", libraryRuntimeType(spec.Result)).(Function)
	ctx := RootExecution()
	for i := 0; i < b.N; i++ {
		fn.Body(ctx, []Value{text, int64(i % len(text))})
	}
}

func BenchmarkBytesSlice(b *testing.B) {
	data := Bytes{bytes.Repeat([]byte("0123456789"), 100000)}
	spec := libraryFunctions["bytes/slice"]
	fn := StandardFunction("bytes/slice", libraryRuntimeType(spec.Result)).(Function)
	ctx := RootExecution()
	for i := 0; i < b.N; i++ {
		fn.Body(ctx, []Value{data, int64(i % 1000), int64(len(data.Items))})
	}
}

func BenchmarkReadLine(b *testing.B) {
	line := strings.Repeat("0123456789", 6) + "\n"
	dir := b.TempDir()
	path := dir + "/log"
	os.WriteFile(path, []byte(strings.Repeat(line, 2000)), 0600)
	spec := libraryFunctions["io/read_line"]
	fn := StandardFunction("io/read_line", libraryRuntimeType(spec.Result)).(Function)
	ctx := RootExecution()
	for i := 0; i < b.N; i++ {
		file, _ := os.Open(path)
		h := &libraryFileHandle{file: file}
		reader := h.Operation("reader").Body(ctx, nil)
		for {
			got := fn.Body(ctx, []Value{reader, int64(1 << 20)}).(Alternative)
			if got.Fields[0].(Alternative).Tag == "none" {
				break
			}
		}
		h.close()
	}
}

func TestForLoopSeesListAsOfLoopStart(t *testing.T) {
	for _, mutate := range []string{"append", "prepend", "with_value", "without"} {
		list := &List{Type: "@std/List[Int]", Items: []Value{int64(1), int64(2), int64(3)}}
		var seen []int64
		for _, item := range Iterate(list) {
			seen = append(seen, item.(int64))
			switch mutate {
			case "append":
				list.Items = append(list.Items, int64(9))
			case "prepend":
				libraryPlain(t, "collections/prepend", list, int64(9))
			case "with_value":
				libraryPlain(t, "collections/with_value", list, int64(0), int64(9))
			case "without":
				libraryPlain(t, "collections/without", list, int64(0))
			}
		}
		if len(seen) != 3 || seen[0] != 1 || seen[1] != 2 || seen[2] != 3 {
			t.Fatalf("%s: loop saw %v", mutate, seen)
		}
	}
}

func BenchmarkIterateEarlyExit(b *testing.B) {
	list := &List{Type: "@std/List[Int]", Items: make([]Value, 1000000)}
	for i := 0; i < b.N; i++ {
		for range Iterate(list) {
			break
		}
	}
}

func BenchmarkBindImplementation(b *testing.B) {
	receiver := customKey(1, "x")
	ctx := RootExecution()
	scope := TypeScope{Module: "a.ms", Args: []TypeScope{}}
	for i := 0; i < b.N; i++ {
		Invoke(ctx, Bind(receiver, "@std/Hashable", "hash", scope), nil)
	}
}

func TestScalarLengthCache(t *testing.T) {
	long := strings.Repeat("aé", 2000)
	other := strings.Repeat("é", 2000)
	for i := 0; i < 2; i++ {
		if got := libraryPlain(t, "string/scalar_length", long); got != int64(4000) {
			t.Fatalf("long: %v", got)
		}
		if got := libraryPlain(t, "string/scalar_length", other); got != int64(2000) {
			t.Fatalf("other: %v", got)
		}
	}
	if got := libraryPlain(t, "string/scalar_length", "héllo"); got != int64(5) {
		t.Fatalf("short: %v", got)
	}
}

func BenchmarkScalarLength(b *testing.B) {
	text := strings.Repeat("ab", 800000)
	spec := libraryFunctions["string/scalar_length"]
	f := StandardFunction("string/scalar_length", libraryRuntimeType(spec.Result)).(Function)
	ctx := RootExecution()
	for i := 0; i < b.N; i++ {
		f.Body(ctx, []Value{text})
	}
}

func TestForLoopSeesSetAndMapAsOfLoopStart(t *testing.T) {
	ctx := RootExecution()
	set := &Set{Type: "@std/Set[Int]"}
	for i := int64(1); i <= 4; i++ {
		set.add(ctx, i)
	}
	var seen []int64
	for _, item := range Iterate(set) {
		seen = append(seen, item.(int64))
		set.removeAt(ctx, 0)
		set.add(ctx, item.(int64)+100)
	}
	if len(seen) != 4 || seen[0] != 1 || seen[1] != 2 || seen[2] != 3 || seen[3] != 4 {
		t.Fatalf("set loop saw %v", seen)
	}
	m := &Map{Type: "@std/Map[Int][Int]"}
	for i := int64(1); i <= 3; i++ {
		m.put(ctx, i, i*10)
	}
	var values []int64
	for _, entry := range Iterate(m) {
		fields := entry.(Record).Fields
		values = append(values, fields["value"].(int64))
		m.put(ctx, fields["key"], int64(-1))
		m.removeAt(ctx, 0)
	}
	if len(values) != 3 || values[0] != 10 || values[1] != 20 || values[2] != 30 {
		t.Fatalf("map loop saw %v", values)
	}
}

func BenchmarkIterateSetEarlyExit(b *testing.B) {
	ctx := RootExecution()
	set := &Set{Type: "@std/Set[Int]"}
	for i := int64(0); i < 100000; i++ {
		set.add(ctx, i)
	}
	for i := 0; i < b.N; i++ {
		for range Iterate(set) {
			break
		}
	}
}

func BenchmarkIterateMap(b *testing.B) {
	ctx := RootExecution()
	m := &Map{Type: "@std/Map[Int][Int]"}
	for i := int64(0); i < 10000; i++ {
		m.put(ctx, i, i)
	}
	for i := 0; i < b.N; i++ {
		for range Iterate(m) {
		}
	}
}

func BenchmarkListAppendDirect(b *testing.B) {
	ctx := &Execution{Context: context.Background()}
	list := &List{Type: "@std/List[Int]"}
	for i := 0; i < b.N; i++ {
		ListAppend(ctx, list, int64(i))
	}
}

func BenchmarkListAppendMember(b *testing.B) {
	ctx := &Execution{Context: context.Background()}
	list := &List{Type: "@std/List[Int]"}
	for i := 0; i < b.N; i++ {
		Invoke(ctx, NativeMemberResult(list, "append", "", TypeScope{}), []Argument{{Value: int64(i)}})
	}
}
