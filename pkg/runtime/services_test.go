package msruntime

import (
	"testing"
)

func TestBuilderSealAndSnapshot(t *testing.T) {
	root := RootExecution()
	builder := newBuilder("@std/ListBuilder[Int]")
	Invoke(root, builder.Operation("append"), []Argument{{"value", int64(1)}})
	snapshot := Invoke(root, builder.Operation("freeze"), nil).(*List)
	failure := recovered(func() { Invoke(root, builder.Operation("append"), []Argument{{"value", int64(2)}}) })
	if _, ok := failure.(Fault); !ok || snapshot.Len() != 1 {
		t.Fatal("sealed builder mutation changed snapshot")
	}
}
