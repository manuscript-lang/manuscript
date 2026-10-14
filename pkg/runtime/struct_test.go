package msruntime

import "testing"

type testPoint struct{ x, y int64 }

func (p *testPoint) StructType() string    { return "test#Point" }
func (p *testPoint) StructNames() []string { return []string{"x", "y"} }
func (p *testPoint) StructGet(i int) Value {
	if i == 0 {
		return ReadField(p, &p.x)
	}
	return ReadField(p, &p.y)
}
func (p *testPoint) StructSet(i int, v Value) {
	if i == 0 {
		WriteField(p, &p.x, v.(int64))
	} else {
		WriteField(p, &p.y, v.(int64))
	}
}
func (p *testPoint) StructClone() Struct { return CopyStruct(p) }

func TestStructGenericOperations(t *testing.T) {
	a, b := &testPoint{1, 2}, &testPoint{1, 2}
	if !Equal(a, b) {
		t.Fatal("structs with equal fields differ")
	}
	SetField(b, "y", int64(3))
	if Equal(a, b) || Field(b, "y") != int64(3) {
		t.Fatal("dynamic field write or inequality failed")
	}
	if Format(a) != "Point(x: 1, y: 2)" {
		t.Fatal("format:", Format(a))
	}
	clone := Clone(a).(*testPoint)
	clone.x = 7
	if a.x != 1 || ConcreteType(a) != "test#Point" {
		t.Fatal("clone shares storage or type is wrong")
	}
	ctx := RootExecution()
	if keyHash(ctx, a) != keyHash(ctx, &testPoint{1, 2}) || keyHash(ctx, a) == keyHash(ctx, b) {
		t.Fatal("structs must hash structurally")
	}
	RegisterStruct("test#Point", func() Struct { return &testPoint{} })
	t.Cleanup(func() { delete(structFactories, "test#Point") })
	built := NewRecord("test#Point", []Argument{{Name: "x", Value: int64(4)}, {Name: "y", Value: int64(5)}}).(*testPoint)
	if built.x != 4 || built.y != 5 {
		t.Fatal("dynamic construction ignored the registered struct")
	}
}

func TestStructFieldsLockWhileConcurrent(t *testing.T) {
	concurrentWork.Store(true)
	t.Cleanup(func() { concurrentWork.Store(false) })
	p := &testPoint{}
	done := make(chan struct{})
	for i := 0; i < 4; i++ {
		go func() {
			for n := int64(0); n < 1000; n++ {
				WriteField(p, &p.x, n)
				ReadField(p, &p.x)
			}
			done <- struct{}{}
		}()
	}
	for i := 0; i < 4; i++ {
		<-done
	}
}
