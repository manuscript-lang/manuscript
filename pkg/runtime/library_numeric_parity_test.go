package msruntime

import (
	"context"
	"math"
	"math/big"
	"strings"
	"testing"
)

func numericParityCall(t *testing.T, name string, args ...Value) Value {
	t.Helper()
	spec, ok := libraryFunctions[name]
	if !ok {
		t.Fatalf("missing numeric function %s", name)
	}
	return StandardFunction(name, libraryRuntimeType(spec.Result)).(Function).Body(RootExecution(), args)
}

func TestNumericParityIntPowerAndBounds(t *testing.T) {
	for _, test := range []struct{ base, exponent, want int64 }{
		{0, 0, 1}, {0, math.MaxInt64, 0}, {-1, math.MaxInt64, -1}, {1, math.MaxInt64, 1},
		{math.MinInt64, 1, math.MinInt64}, {math.MaxInt64, 1, math.MaxInt64}, {-2, 63, math.MinInt64}, {2, 62, 1 << 62},
	} {
		if got := librarySuccess(t, numericParityCall(t, "math/pow_int", test.base, test.exponent)); got != test.want {
			t.Fatalf("%d^%d = %v, want %d", test.base, test.exponent, got, test.want)
		}
	}
	for _, test := range []struct{ base, exponent int64 }{{2, 63}, {-2, 64}, {math.MinInt64, 2}, {math.MaxInt64, 2}} {
		libraryFailure(t, numericParityCall(t, "math/pow_int", test.base, test.exponent), "OutOfRange")
	}
	libraryFailure(t, numericParityCall(t, "math/pow_int", int64(0), int64(-1)), "InvalidInput")
	if numericParityCall(t, "math/min_int", int64(math.MaxInt64), int64(math.MinInt64)) != int64(math.MinInt64) ||
		numericParityCall(t, "math/max_int", int64(math.MaxInt64), int64(math.MinInt64)) != int64(math.MaxInt64) {
		t.Fatal("integer extrema lost signed 64-bit precision")
	}
	if numericParityCall(t, "math/clamp_int", int64(math.MinInt64), int64(-5), int64(5)) != int64(-5) ||
		numericParityCall(t, "math/clamp_int", int64(math.MaxInt64), int64(-5), int64(5)) != int64(5) {
		t.Fatal("integer clamping lost signed 64-bit precision")
	}
	for _, value := range []int64{math.MinInt64, 0, math.MaxInt64} {
		want := int64(0)
		if value < 0 {
			want = -1
		} else if value > 0 {
			want = 1
		}
		if numericParityCall(t, "math/sign_int", value) != want {
			t.Fatal("integer sign")
		}
	}
}

func TestNumericParityFloatConversions(t *testing.T) {
	for name, wants := range map[string][]int64{
		"round_to_int": {-1, 3, -3}, "floor_to_int": {-2, 2, -4}, "ceil_to_int": {-1, 3, -3},
	} {
		for i, input := range []float64{-1.5, 2.5, -3.1} {
			if got := numericParityCall(t, "math/"+name, input); !Equal(got, optional("Int", wants[i], true)) {
				t.Fatalf("%s(%v) = %#v", name, input, got)
			}
		}
		for _, input := range []float64{math.NaN(), math.Inf(-1), math.Inf(1), 9223372036854775808.0, math.Nextafter(-9223372036854775808.0, math.Inf(-1))} {
			if got := numericParityCall(t, "math/"+name, input).(Alternative); got.Tag != "none" {
				t.Fatalf("%s(%v) = %#v, want none", name, input, got)
			}
		}
		for _, input := range []float64{-9223372036854775808.0, math.Nextafter(9223372036854775808.0, 0)} {
			if got := numericParityCall(t, "math/"+name, input); !Equal(got, optional("Int", int64(input), true)) {
				t.Fatalf("%s rejected representable boundary %v", name, input)
			}
		}
	}
	negativeZero := math.Copysign(0, -1)
	if got := numericParityCall(t, "math/sign", negativeZero).(float64); got != 0 || !math.Signbit(got) {
		t.Fatal("sign discarded negative zero")
	}
	for _, input := range []float64{math.NaN(), math.Inf(-1), math.Inf(1), -2, 2} {
		got := numericParityCall(t, "math/sign", input).(float64)
		if math.IsNaN(input) && !math.IsNaN(got) || !math.IsNaN(input) && got != math.Copysign(1, input) {
			t.Fatal("floating sign")
		}
	}
	if numericParityCall(t, "math/cbrt", -8.0) != -2.0 || numericParityCall(t, "math/asinh", 0.0) != 0.0 ||
		numericParityCall(t, "math/acosh", 1.0) != 0.0 || numericParityCall(t, "math/atanh", 0.0) != 0.0 {
		t.Fatal("cube root or inverse hyperbolic identities")
	}
	if !math.IsNaN(numericParityCall(t, "math/acosh", 0.5).(float64)) || !math.IsInf(numericParityCall(t, "math/atanh", 1.0).(float64), 1) {
		t.Fatal("inverse hyperbolic domain edges")
	}
	if numericParityCall(t, "math/clamp", -3.0, -2.0, 2.0) != -2.0 {
		t.Fatal("floating clamp")
	}
	for i := range 3 {
		args := []Value{0.0, -2.0, 2.0}
		args[i] = math.NaN()
		if !math.IsNaN(numericParityCall(t, "math/clamp", args...).(float64)) {
			t.Fatal("clamp failed to propagate NaN")
		}
	}
}

func TestNumericParityClampDiagnostics(t *testing.T) {
	for name, args := range map[string][]Value{
		"clamp": {0.0, 3.0, -2.0}, "clamp_int": {int64(0), int64(3), int64(-2)},
	} {
		failure := recovered(func() { numericParityCall(t, "math/"+name, args...) })
		fault, ok := failure.(Fault)
		if !ok || !strings.Contains(fault.Message, "minimum must be <= maximum") || !strings.Contains(fault.Message, "minimum 3 and maximum -2") {
			t.Fatalf("%s fault = %#v", name, failure)
		}
	}
}

func TestNumericParityBigIntOperations(t *testing.T) {
	value := libraryBigInt{big.NewInt(-7)}
	for name, want := range map[string]int64{"negate": 7, "abs": 7, "bit_not": 6} {
		got := numericParityCall(t, "bigint/"+name, value).(libraryBigInt)
		if got.n.Int64() != want || value.n.Int64() != -7 || got.n == value.n {
			t.Fatal("unary bigint operation changed its receiver or reused its storage")
		}
	}
	for _, option := range []Value{nil, optional("Int", nil, false), int64(9), optional("Int", int64(9), true)} {
		got := librarySuccess(t, numericParityCall(t, "bigint/pow", value, int64(3), option)).(libraryBigInt)
		if got.n.Int64() != -343 || value.n.Int64() != -7 {
			t.Fatal("big integer power or alias identity")
		}
	}
	for _, test := range []struct {
		name string
		args []Value
		code string
	}{
		{"pow", []Value{value, int64(-1)}, "InvalidInput"},
		{"pow", []Value{value, int64(3), optional("Int", int64(-1), true)}, "InvalidInput"},
		{"pow", []Value{value, int64(3), int64(8)}, "LimitExceeded"},
		{"pow", []Value{libraryBigInt{big.NewInt(2)}, int64(math.MaxInt64)}, "LimitExceeded"},
		{"pow", []Value{value, int64(0), int64(0)}, "LimitExceeded"},
		{"shift_left", []Value{value, int64(-1)}, "InvalidInput"},
		{"shift_left", []Value{value, int64(math.MaxInt64)}, "LimitExceeded"},
		{"shift_left", []Value{value, int64(2), int64(4)}, "LimitExceeded"},
		{"shift_left", []Value{value, int64(2), int64(-1)}, "InvalidInput"},
		{"shift_right", []Value{value, int64(-1)}, "InvalidInput"},
	} {
		libraryFailure(t, numericParityCall(t, "bigint/"+test.name, test.args...), test.code)
	}
	for _, test := range []struct {
		name  string
		value int64
		count int64
		want  int64
	}{
		{"shift_left", -7, 2, -28}, {"shift_left", 0, math.MaxInt64, 0},
		{"shift_right", -7, 1, -4}, {"shift_right", -7, math.MaxInt64, -1}, {"shift_right", 7, math.MaxInt64, 0},
	} {
		got := librarySuccess(t, numericParityCall(t, "bigint/"+test.name, libraryBigInt{big.NewInt(test.value)}, test.count)).(libraryBigInt)
		if got.n.Int64() != test.want {
			t.Fatalf("%s(%d, %d) = %s", test.name, test.value, test.count, got.n)
		}
	}
	if got := librarySuccess(t, numericParityCall(t, "bigint/pow", libraryBigInt{big.NewInt(0)}, int64(math.MaxInt64), int64(0))).(libraryBigInt); got.n.Sign() != 0 {
		t.Fatal("zero power exceeded an empty magnitude budget")
	}
	if got := librarySuccess(t, numericParityCall(t, "bigint/pow", libraryBigInt{big.NewInt(0)}, int64(0))).(libraryBigInt); got.n.Int64() != 1 {
		t.Fatal("zero to zero power")
	}
}

func TestNumericParityDecimalExactRounding(t *testing.T) {
	for _, test := range []struct{ input, operation, want string }{
		{"-1.5d", "floor_to_int", "-2"}, {"-1.5d", "ceil_to_int", "-1"},
		{"2.5d", "round_to_int", "2"}, {"3.5d", "round_to_int", "4"},
		{"-2.5d", "round_to_int", "-2"}, {"-3.5d", "round_to_int", "-4"},
		{"9007199254740993.1d", "floor_to_int", "9007199254740993"},
		{"-9223372036854775808.5d", "round_to_int", "-9223372036854775808"},
		{"9223372036854775807.1d", "floor_to_int", "9223372036854775807"},
	} {
		input := DecimalLiteral(test.input).(Decimal)
		before := new(big.Rat).Set(input.Value)
		got := numericParityCall(t, "decimal/"+test.operation, input).(Alternative)
		if got.Tag != "some" || Format(got.Fields[0]) != test.want || input.Value.Cmp(before) != 0 {
			t.Fatalf("%s.%s() = %#v", test.input, test.operation, got)
		}
	}
	for _, test := range []struct{ input, operation string }{
		{"9223372036854775807.5d", "round_to_int"}, {"9223372036854775807.1d", "ceil_to_int"},
		{"-9223372036854775808.1d", "floor_to_int"}, {"1e6144d", "round_to_int"},
	} {
		if got := numericParityCall(t, "decimal/"+test.operation, DecimalLiteral(test.input)).(Alternative); got.Tag != "none" {
			t.Fatal("decimal integer overflow did not return none")
		}
	}
	negative := DecimalLiteral("-9007199254740993.1d").(Decimal)
	if got := numericParityCall(t, "decimal/abs", negative).(Decimal); got.Value.Sign() < 0 || negative.Value.Sign() >= 0 || got.Value == negative.Value {
		t.Fatal("decimal absolute value changed its receiver")
	}
	if numericParityCall(t, "decimal/compare", DecimalLiteral("9007199254740993d"), DecimalLiteral("9007199254740992d")) != int64(1) {
		t.Fatal("decimal comparison used binary floating precision")
	}
}

func TestNumericParityBoundCallsAndCancellation(t *testing.T) {
	for _, test := range []struct {
		receiver Value
		method   string
		args     []Argument
		want     Value
	}{
		{-1.5, "round_to_int", nil, optional("Int", int64(-1), true)},
		{DecimalLiteral("2.5d"), "round_to_int", nil, optional("Int", int64(2), true)},
		{libraryBigInt{big.NewInt(-7)}, "shift_right", []Argument{{"count", int64(1)}}, libraryOK("@std/Result[@std/BigInt][@std/BigIntError]", libraryBigInt{big.NewInt(-4)})},
	} {
		bound := Bind(test.receiver, "", test.method)
		if got := Invoke(RootExecution(), bound, test.args); !Equal(got, test.want) {
			t.Fatalf("bound %s = %#v", test.method, got)
		}
	}
	for _, test := range []struct {
		name string
		args []Value
	}{
		{"math/pow_int", []Value{int64(2), int64(63)}},
		{"bigint/pow", []Value{libraryBigInt{big.NewInt(2)}, int64(math.MaxInt64)}},
		{"bigint/shift_left", []Value{libraryBigInt{big.NewInt(1)}, int64(3)}},
		{"bigint/shift_right", []Value{libraryBigInt{big.NewInt(1)}, int64(3)}},
		{"math/sum_int", []Value{libraryList("Int", nil)}},
		{"math/sum_float", []Value{libraryList("Float", nil)}},
	} {
		execution := RootExecution()
		lifetime, cancel := context.WithCancel(execution.Context)
		cancel()
		execution.Context = lifetime
		spec := libraryFunctions[test.name]
		failure := recovered(func() { spec.Body(execution, libraryRuntimeType(spec.Result), test.args) })
		if _, ok := failure.(cancelled); !ok {
			t.Fatalf("%s cancellation became %#v", test.name, failure)
		}
	}
}

func TestNumericParitySums(t *testing.T) {
	for _, test := range []struct {
		values []Value
		want   int64
	}{
		{nil, 0}, {[]Value{int64(math.MinInt64), int64(math.MaxInt64)}, -1},
		{[]Value{int64(math.MaxInt64), int64(-1), int64(1)}, math.MaxInt64},
		{[]Value{int64(math.MinInt64), int64(1), int64(-1)}, math.MinInt64},
	} {
		list := libraryList("Int", test.values)
		if got := librarySuccess(t, numericParityCall(t, "math/sum_int", list)); got != test.want {
			t.Fatalf("integer sum = %v, want %d", got, test.want)
		}
		if list.Len() != len(test.values) {
			t.Fatal("sum changed list storage")
		}
		for i, value := range test.values {
			if list.Get(i) != value {
				t.Fatal("sum changed an input value")
			}
		}
	}
	for _, values := range [][]Value{
		{int64(math.MaxInt64), int64(1)}, {int64(math.MinInt64), int64(-1)},
		{int64(math.MaxInt64), int64(1), int64(-1)},
	} {
		libraryFailure(t, numericParityCall(t, "math/sum_int", libraryList("Int", values)), "OutOfRange")
	}
	if numericParityCall(t, "math/sum_float", libraryList("Float", nil)) != float64(0) ||
		numericParityCall(t, "math/sum_float", libraryList("Float", []Value{1.5, -2.0, 3.0})) != 2.5 {
		t.Fatal("floating sum identity or addition")
	}
	for _, values := range [][]Value{{math.NaN()}, {math.Inf(1), math.Inf(-1)}} {
		if !math.IsNaN(numericParityCall(t, "math/sum_float", libraryList("Float", values)).(float64)) {
			t.Fatal("floating sum did not preserve IEEE NaN")
		}
	}
	if !math.IsInf(numericParityCall(t, "math/sum_float", libraryList("Float", []Value{math.MaxFloat64, math.MaxFloat64})).(float64), 1) {
		t.Fatal("floating sum overflow changed IEEE behavior")
	}
}

type numericParityMutationContext struct {
	context.Context
	checks int
	onErr  func(int)
}

func (ctx *numericParityMutationContext) Err() error {
	ctx.checks++
	ctx.onErr(ctx.checks)
	return ctx.Context.Err()
}

func TestNumericParitySumCapturedTypedAndBoxedStorage(t *testing.T) {
	for _, kind := range []string{"Int", "Float"} {
		for _, boxed := range []bool{false, true} {
			for _, spare := range []bool{false, true} {
				t.Run(kind+"/boxed="+Format(boxed)+"/spare="+Format(spare), func(t *testing.T) {
					typ, operation, want, replacement := "@std/List[Int]", "sum_int", Value(int64(6)), Value(int64(20))
					values := []Value{int64(1), int64(2), int64(3)}
					if kind == "Float" {
						typ, operation, want, replacement = "@std/List[Float]", "sum_float", 7.5, 20.5
						values = []Value{1.5, 2.5, 3.5}
					}
					list := NewList(typ, values)
					if boxed {
						list = &List{Type: typ, Items: append([]Value(nil), values...)}
					}
					if spare {
						list.Append(values[0])
						list.truncate(3)
						if kind == "Float" {
							want = 25.5
						} else {
							want = int64(24)
						}
					}
					storageKind := list.kind
					ctx := RootExecution()
					ctx.Context = &numericParityMutationContext{Context: ctx.Context, onErr: func(check int) {
						if check == 2 {
							list.Append(values[0])
							list.Set(1, replacement)
						}
					}}
					spec := libraryFunctions["math/"+operation]
					got := spec.Body(ctx, libraryRuntimeType(spec.Result), []Value{list})
					if kind == "Int" {
						got = librarySuccess(t, got)
					}
					if got != want || list.Len() != 4 || list.kind != storageKind {
						t.Fatalf("captured %s sum = %v, want %v; list length/kind %d/%d", kind, got, want, list.Len(), list.kind)
					}
					if !boxed && list.Items != nil {
						t.Fatal("sum created a boxed mirror of typed backing")
					}
				})
			}
		}
	}
	for _, kind := range []string{"Int", "Float"} {
		for _, boxed := range []bool{false, true} {
			values, typ, operation := make([]Value, 1024), "@std/List[Int]", "sum_int"
			for i := range values {
				values[i] = int64(1)
			}
			if kind == "Float" {
				typ, operation = "@std/List[Float]", "sum_float"
				for i := range values {
					values[i] = 1.0
				}
			}
			list := NewList(typ, values)
			if boxed {
				list = &List{Type: typ, Items: values}
			}
			ctx := RootExecution()
			lifetime, cancel := context.WithCancel(ctx.Context)
			defer cancel()
			work := &numericParityMutationContext{Context: lifetime, onErr: func(check int) {
				if check == 3 {
					cancel()
				}
			}}
			ctx.Context = work
			spec := libraryFunctions["math/"+operation]
			failure := recovered(func() { spec.Body(ctx, libraryRuntimeType(spec.Result), []Value{list}) })
			if _, ok := failure.(cancelled); !ok || work.checks != 3 || list.Len() != 1024 || list.Get(0) != values[0] {
				t.Fatalf("%s boxed=%t sum failed to cancel after a traversal chunk: %#v (%d checks)", kind, boxed, failure, work.checks)
			}
		}
	}
}
