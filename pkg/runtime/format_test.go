package msruntime

import (
	"math/big"
	"regexp"
	"strings"
	"testing"
	"time"
)

type uninspectableResource struct{}

func (uninspectableResource) Operation(string) Function {
	panic("formatting must not invoke native operations")
}

func TestUniversalFormatting(t *testing.T) {
	for _, test := range []struct {
		name  string
		value Value
		want  string
	}{
		{"empty record", Record{Type: "module/123#Empty", Fields: map[string]Value{}}, "Empty()"},
		{"field order", Record{Type: "module/123#Point[Int]", Fields: map[string]Value{"z": int32(2), "a": true}}, "Point(a: true, z: 2)"},
		{"alternative", Alternative{Type: "@std/Result[Int][String]", Tag: "ok", Fields: []Value{int32(3)}}, "Result.ok(3)"},
		{"empty map", &Map{}, "Map()"},
		{"empty set", &Set{}, "Set()"},
		{"empty bytes", Bytes{}, "Bytes()"},
		{"duration", Duration(-2000000), "-2000000ns"},
		{"instant", Instant{Tick: 42}, "Instant(42)"},
		{"operation", OperationId{number: 7}, "OperationId(7)"},
		{"bigint", libraryBigInt{big.NewInt(123)}, "123"},
		{"timestamp", libraryTimestamp{time.Date(2026, 10, 11, 12, 0, 0, 100, time.FixedZone("offset", 3600))}, "2026-10-11T11:00:00.0000001Z"},
		{"regex", libraryRegex{regexp.MustCompile("a+")}, "a+"},
		{"function", Function{}, "[function]"},
		{"generic", Generic{}, "[function]"},
		{"resource", uninspectableResource{}, "[object]"},
		{"view", View{Type: "Named", Receiver: int32(3)}, "3"},
		{"resource view", View{Type: "Resource", Receiver: uninspectableResource{}}, "[object]"},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := Format(test.value); got != test.want {
				t.Fatalf("got %q, want %q", got, test.want)
			}
			ctx := RootExecution()
			defer FinishExecution(ctx)
			for _, method := range []Value{NativeMember(test.value, "toString"), Bind(test.value, "Resource", "toString")} {
				if method.(Function).Result != "String" {
					t.Fatal("toString must return String")
				}
				if got := Invoke(ctx, method, nil); got != test.want {
					t.Fatalf("bound method returned %q, want %q", got, test.want)
				}
			}
		})
	}
}

func TestFormattingCyclesAndSharedValues(t *testing.T) {
	fields := map[string]Value{}
	value := Record{Type: "Node", Fields: fields}
	fields["next"] = value
	if got := Format(value); !strings.Contains(got, "next: ...") || len(got) > 1000 {
		t.Fatal("cyclic value did not terminate", got)
	}
	shared := Record{Type: "Leaf", Fields: map[string]Value{"value": int32(1)}}
	if got := Format(&List{Items: []Value{shared, shared}}); got != "[Leaf(value: 1), Leaf(value: 1)]" {
		t.Fatal("sharing changed formatting", got)
	}
}
