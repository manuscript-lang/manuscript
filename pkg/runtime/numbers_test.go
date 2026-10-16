package msruntime

import (
	"context"
	"math"
	"reflect"
	"strings"
	"testing"
)

func TestParseNumbers(t *testing.T) {
	for _, tt := range []struct {
		text  string
		radix int
		want  int
		err   string
	}{
		{"-ff", 16, -255, ""}, {"+z", 36, 35, ""}, {"1", 1, 0, "InvalidInput"}, {"1", 37, 0, "InvalidInput"},
		{"", 10, 0, "InvalidData"}, {"-", 10, 0, "InvalidData"}, {"12", 2, 0, "InvalidData"},
		{"9223372036854775808", 10, 0, "OutOfRange"}, {"-9223372036854775808", 10, math.MinInt64, ""},
	} {
		r := Numbers_ParseInt(tctx, tt.text, tt.radix)
		if tt.err == "" {
			if r.Failed || r.Val != tt.want {
				t.Errorf("%q/%d: %v", tt.text, tt.radix, r)
			}
		} else if !r.Failed || !strings.HasSuffix(reflect.TypeOf(r.Err).Name(), tt.err) {
			t.Errorf("%q/%d: %v", tt.text, tt.radix, r)
		}
	}
	for text, want := range map[string]float64{"1.5": 1.5, "-2e3": -2000, "+0.25E-1": 0.025} {
		if r := Numbers_ParseFloat(tctx, text); r.Failed || r.Val != want {
			t.Errorf("%q: %v", text, r)
		}
	}
	if r := Numbers_ParseFloat(tctx, "-Infinity"); r.Failed || !math.IsInf(r.Val, -1) {
		t.Error("-Infinity")
	}
	for _, bad := range []string{"", ".5", "5.", "1e", "0x10", "inf", " 1"} {
		if r := Numbers_ParseFloat(tctx, bad); !r.Failed {
			t.Errorf("accepted %q", bad)
		} else if _, ok := r.Err.(NumberError_InvalidData); !ok {
			t.Errorf("%q: %T", bad, r.Err)
		}
	}
	if r := Numbers_ParseFloat(tctx, "1e999"); !r.Failed {
		t.Error("overflow accepted")
	} else if _, ok := r.Err.(NumberError_OutOfRange); !ok {
		t.Error("overflow case")
	}
}

func TestFloatFormatting(t *testing.T) {
	tenth, fifth := 0.1, 0.2
	for _, tt := range []struct {
		name string
		got  Result[string, NumberError]
		want string
	}{
		{"fixed", Float_ToFixed(tctx, 1.005, 2), "1.00"},
		{"fixed zero", Float_ToFixed(tctx, 2.5, 0), "2"},
		{"fixed big", Float_ToFixed(tctx, 1e21, 2), "1e+21"},
		{"exp", Float_ToExponential(tctx, 12345.678, 2), "1.23e+4"},
		{"exp small", Float_ToExponential(tctx, 0.00012, 0), "1e-4"},
		{"precision", Float_ToPrecision(tctx, 1.5, 4), "1.500"},
		{"precision exp", Float_ToPrecision(tctx, 123456, 2), "1.2e+5"},
		{"nan", Float_ToFixed(tctx, math.NaN(), 2), "NaN"},
	} {
		if tt.got.Failed || tt.got.Val != tt.want {
			t.Errorf("%s: %v want %s", tt.name, tt.got, tt.want)
		}
	}
	if !Float_ToPrecision(tctx, 1, 0).Failed || !Float_ToPrecision(tctx, 1, 101).Failed || !Float_ToFixed(tctx, 1, -1).Failed || !Float_ToExponential(tctx, 1, 101).Failed {
		t.Fatal("invalid digit counts")
	}
	if Float_ToString(tctx, tenth+fifth) != "0.30000000000000004" || Float_ToString(tctx, math.Copysign(0, -1)) != "-0" {
		t.Fatal("to_string")
	}
	if Float_TruncateToInt(tctx, -2.9) != Some(int(-2)) || Float_TruncateToInt(tctx, 9223372036854775808.0).Some || Float_TruncateToInt(tctx, math.NaN()).Some || !Float_TruncateToInt(tctx, -9223372036854775808.0).Some {
		t.Fatal("truncate_to_int")
	}
	if !Float_IsNan(tctx, math.NaN()) || Float_IsFinite(tctx, math.Inf(1)) || !Float_IsFinite(tctx, 1) {
		t.Fatal("classification")
	}
}

func TestIntOperations(t *testing.T) {
	if Int_ToString(tctx, -255, 16) != "-ff" || Int_ToString(tctx, 35, 36) != "z" {
		t.Fatal("radix")
	}
	if got := faultMessage(func() { Int_ToString(tctx, 1, 37) }); got != "Int.to_string: radix must be between 2 and 36, found 37" {
		t.Fatalf("radix fault %q", got)
	}
	if Int_Seconds(tctx, 2) != Duration(2e9) || Int_Minutes(tctx, 1) != Duration(60e9) || Int_Milliseconds(tctx, 3) != Duration(3e6) {
		t.Fatal("durations")
	}
	if got := faultMessage(func() { Int_Minutes(tctx, math.MaxInt64) }); !strings.HasPrefix(got, "Int.minutes: value must be between ") || !strings.HasSuffix(got, "found 9223372036854775807") {
		t.Fatalf("duration fault %q", got)
	}
	if Int_ToFloat(tctx, 1<<53+1) != float64(1<<53) {
		t.Fatal("to_float")
	}
}

func TestMath(t *testing.T) {
	if Math_Round(tctx, 2.5) != 3 || Math_Round(tctx, -2.5) != -2 || Math_Round(tctx, -0.4) != 0 || !math.Signbit(Math_Round(tctx, -0.4)) {
		t.Fatal("round")
	}
	if Math_Remainder(tctx, -7, 3) != -1 || Math_Truncate(tctx, -1.9) != -1 || Math_Pi(tctx) != math.Pi || Math_E(tctx) != math.E {
		t.Fatal("scalars")
	}
	if Math_AbsInt(tctx, -5) != 5 {
		t.Fatal("abs_int")
	}
	if got := faultMessage(func() { Math_AbsInt(tctx, math.MinInt64) }); !strings.HasPrefix(got, "Int overflow;") {
		t.Fatalf("abs_int fault %q", got)
	}
}

func TestBigInt(t *testing.T) {
	big := func(text string) *BigInt {
		r := Bigint_Parse(tctx, text, 10, None[int]())
		if r.Failed {
			t.Fatalf("parse %q", text)
		}
		return r.Val
	}
	a, b := big("-7"), big("2")
	if q := BigInt_Divide(tctx, a, b).Val; q.String() != "-3" {
		t.Fatal("divide")
	}
	if r := BigInt_Remainder(tctx, a, b).Val; r.String() != "-1" {
		t.Fatal("remainder")
	}
	if !BigInt_Divide(tctx, a, big("0")).Failed || !BigInt_Remainder(tctx, a, big("0")).Failed {
		t.Fatal("zero divisor")
	}
	if BigInt_BitAnd(tctx, a, big("255")).String() != "249" || BigInt_BitOr(tctx, a, b).String() != "-5" || BigInt_BitXor(tctx, a, b).String() != "-5" {
		t.Fatal("bit ops")
	}
	huge := BigInt_Multiply(tctx, big("9223372036854775807"), big("9223372036854775807"))
	if BigInt_ToInt(tctx, huge).Some || BigInt_ToInt(tctx, a) != Some(int(-7)) {
		t.Fatal("to_int")
	}
	if BigInt_Compare(tctx, a, b) != -1 || BigInt_Compare(tctx, b, b) != 0 || BigInt_Add(tctx, a, b).String() != "-5" || BigInt_Subtract(tctx, a, b).String() != "-9" {
		t.Fatal("arithmetic")
	}
	if BigInt_ToString(tctx, Bigint_FromInt(tctx, 35), 36) != "z" || BigInt_ToString(tctx, Bigint_FromInt(tctx, -35), 2) != "-100011" {
		t.Fatal("radix")
	}
	if got := faultMessage(func() { BigInt_ToString(tctx, a, 1) }); got != "BigInt.to_string: radix must be between 2 and 36, found 1" {
		t.Fatalf("radix fault %q", got)
	}
	for _, tt := range []struct {
		text  string
		radix int
		max   Option[int]
		err   string
	}{
		{"12", 1, None[int](), "BigIntError_InvalidInput"}, {"12", 10, Some(int(-1)), "BigIntError_InvalidInput"},
		{"-123", 10, Some(int(2)), "BigIntError_LimitExceeded"}, {"zz!", 10, Some(int(1)), "BigIntError_LimitExceeded"},
		{"1x", 10, None[int](), "BigIntError_InvalidData"}, {"", 10, None[int](), "BigIntError_InvalidData"},
	} {
		r := Bigint_Parse(tctx, tt.text, tt.radix, tt.max)
		if !r.Failed || reflect.TypeOf(r.Err).Name() != tt.err {
			t.Errorf("%q: %v", tt.text, r)
		}
	}
	if r := Bigint_Parse(tctx, "-123", 10, Some(int(3))); r.Failed || r.Val.String() != "-123" {
		t.Fatal("sign is not a digit")
	}
}

func TestBytesOperations(t *testing.T) {
	data := NewBytes([]byte{1, 0, 2, 0, 3})
	if Bytes_At(tctx, data, -1) != Some(int(3)) || Bytes_At(tctx, data, 5).Some || Bytes_At(tctx, data, -6).Some {
		t.Fatal("at")
	}
	if r := Bytes_Slice(tctx, data, 1, -1); r.Failed || !reflect.DeepEqual(r.Val.Data, []byte{0, 2, 0}) || cap(r.Val.Data) != 3 {
		t.Fatalf("slice %v", r)
	}
	if !Bytes_Slice(tctx, data, 3, 2).Failed {
		t.Fatal("inverted slice")
	}
	updated := Bytes_WithValue(tctx, data, -1, 255)
	if updated.Data[4] != 255 || data.Data[4] != 3 {
		t.Fatal("with_value copies")
	}
	if got := faultMessage(func() { Bytes_WithValue(tctx, data, 5, 1) }); got != "Bytes.with_value: index must be between -5 and 4 (negative indexes count from the end), found 5" {
		t.Fatalf("index fault %q", got)
	}
	if got := faultMessage(func() { Bytes_WithValue(tctx, NewBytes(nil), 0, 1) }); got != "Bytes.with_value: index has no valid value for an empty collection, found 0" {
		t.Fatalf("empty fault %q", got)
	}
	if got := faultMessage(func() { Bytes_WithValue(tctx, data, 0, 300) }); got != "Bytes.with_value: value must be between 0 and 255, found 300" {
		t.Fatalf("value fault %q", got)
	}
	zero := NewBytes([]byte{0})
	if Bytes_IndexOf(tctx, data, zero) != Some(int(1)) || Bytes_LastIndexOf(tctx, data, zero) != Some(int(3)) || Bytes_IndexOf(tctx, data, NewBytes(nil)) != Some(int(0)) || Bytes_LastIndexOf(tctx, data, NewBytes(nil)) != Some(int(5)) {
		t.Fatal("index_of")
	}
	if !Bytes_StartsWith(tctx, data, NewBytes([]byte{1, 0})) || !Bytes_EndsWith(tctx, data, NewBytes([]byte{0, 3})) || !Bytes_Contains(tctx, data, NewBytes([]byte{2, 0})) {
		t.Fatal("affixes")
	}
	if !reflect.DeepEqual(Bytes_Reversed(tctx, data).Data, []byte{3, 0, 2, 0, 1}) || !reflect.DeepEqual(Bytes_Values(tctx, data).Items, []int{1, 0, 2, 0, 3}) {
		t.Fatal("reversed/values")
	}
	if !reflect.DeepEqual(Bytes_Concat(tctx, data, zero).Data, []byte{1, 0, 2, 0, 3, 0}) || Bytes_Length(tctx, data) != 5 || Bytes_IsEmpty(tctx, data) {
		t.Fatal("concat")
	}
	if clone := Bytes_Clone(tctx, data); &clone.Data[0] == &data.Data[0] {
		t.Fatal("clone shares storage")
	}
	if Bytes_ToString(tctx, NewBytes([]byte("é"))) != Some("é") || Bytes_ToString(tctx, NewBytes([]byte{0xff})).Some {
		t.Fatal("to_string")
	}
}

func TestBytesSplitSharesImmutableViewsAndCopiesOuterStorage(t *testing.T) {
	data := NewBytes([]byte{1, 0, 2})
	first := Bytes_Split(tctx, data, NewBytes([]byte{0}), None[int]())
	second := Bytes_Split(tctx, data, NewBytes([]byte{0}), None[int]())
	if first == second || &first.Items[0] == &second.Items[0] {
		t.Fatal("byte parts share outer storage")
	}
	for i, offset := range []int{0, 2} {
		part := first.Items[i]
		if len(part.Data) != 1 || &part.Data[0] != &data.Data[offset] {
			t.Fatal("byte part copied immutable backing storage", i)
		}
	}
	if got := Bytes_Split(tctx, NewBytes(nil), NewBytes([]byte{0}), None[int]()); len(got.Items) != 1 || len(got.Items[0].Data) != 0 {
		t.Fatal("empty data, nonempty separator yields one empty part")
	}
	if got := Bytes_Split(tctx, NewBytes(nil), NewBytes(nil), None[int]()); len(got.Items) != 0 {
		t.Fatal("empty data, empty separator yields none")
	}
	if got := Bytes_Split(tctx, NewBytes([]byte{1, 2, 3}), NewBytes(nil), Some(int(2))); len(got.Items) != 2 {
		t.Fatal("empty separator capped")
	}
	if got := Bytes_Split(tctx, NewBytes([]byte{1, 0, 2, 0, 3}), NewBytes([]byte{0}), Some(int(2))); len(got.Items) != 2 {
		t.Fatal("cap truncates")
	}
	if got := faultMessage(func() { Bytes_Split(tctx, data, NewBytes([]byte{0}), Some(int(-7))) }); got != "split: max_parts must be nonnegative, found -7" {
		t.Fatalf("split fault %q", got)
	}
}

func TestBytesSplitCancellation(t *testing.T) {
	for _, separator := range [][]byte{nil, {0}} {
		ctx := RootExecution()
		cancelCtx, cancel := context.WithCancel(ctx.Context)
		cancel()
		ctx.Context = cancelCtx
		func() {
			defer func() {
				if _, ok := recover().(cancelled); !ok {
					t.Fatal("cancelled split did not unwind")
				}
			}()
			Bytes_Split(ctx, NewBytes([]byte(strings.Repeat("a\x00", 4096))), NewBytes(separator), None[int]())
		}()
	}
}

func TestBytesBuilder(t *testing.T) {
	b := NewBytesBuilder()
	BytesBuilder_Append(tctx, b, 0)
	BytesBuilder_Append(tctx, b, 255)
	BytesBuilder_Concat(tctx, b, NewBytes([]byte{7}))
	if got := faultMessage(func() { BytesBuilder_Append(tctx, b, 256) }); got != "BytesBuilder.append: value must be between 0 and 255, found 256" {
		t.Fatalf("range fault %q", got)
	}
	frozen := BytesBuilder_Freeze(tctx, b)
	if !reflect.DeepEqual(frozen.Data, []byte{0, 255, 7}) || !reflect.DeepEqual(BytesBuilder_Freeze(tctx, b).Data, frozen.Data) {
		t.Fatal("freeze")
	}
	if got := faultMessage(func() { BytesBuilder_Append(tctx, b, 1) }); got != "builder is sealed" {
		t.Fatalf("sealed %q", got)
	}
}

func TestEncoding(t *testing.T) {
	data := NewBytes([]byte{0xfb, 0xff, 0x00})
	if Encoding_HexEncode(tctx, data) != "fbff00" || Encoding_Base64Encode(tctx, data, false) != "+/8A" || Encoding_Base64Encode(tctx, data, true) != "-_8A" {
		t.Fatal("encode")
	}
	if r := Encoding_HexDecode(tctx, "FBff00", None[int]()); r.Failed || !reflect.DeepEqual(r.Val.Data, data.Data) {
		t.Fatal("hex decode")
	}
	if r := Encoding_HexDecode(tctx, "abc", None[int]()); !r.Failed {
		t.Fatal("odd hex")
	} else if _, ok := r.Err.(EncodingError_InvalidData); !ok {
		t.Fatal("odd hex case")
	}
	if r := Encoding_HexDecode(tctx, "aabb", Some(int(1))); !r.Failed {
		t.Fatal("hex budget")
	} else if _, ok := r.Err.(EncodingError_LimitExceeded); !ok {
		t.Fatal("hex budget case")
	}
	if r := Encoding_HexDecode(tctx, "aa", Some(int(-1))); !r.Failed {
		t.Fatal("negative budget")
	} else if _, ok := r.Err.(EncodingError_InvalidInput); !ok {
		t.Fatal("negative budget case")
	}
	if r := Encoding_Base64Decode(tctx, "+/8A", false, None[int]()); r.Failed || !reflect.DeepEqual(r.Val.Data, data.Data) {
		t.Fatal("base64 decode")
	}
	if r := Encoding_Base64Decode(tctx, "-_8A", true, None[int]()); r.Failed || !reflect.DeepEqual(r.Val.Data, data.Data) {
		t.Fatal("url-safe decode")
	}
	for _, bad := range []string{"-_8A", "+/8", "+/8A\n", "====", "QQ=", "QR=="} {
		if r := Encoding_Base64Decode(tctx, bad, false, None[int]()); !r.Failed {
			t.Errorf("accepted %q", bad)
		}
	}
	if r := Encoding_Base64Decode(tctx, "+/8A", false, Some(int(2))); !r.Failed {
		t.Fatal("base64 budget")
	} else if _, ok := r.Err.(EncodingError_LimitExceeded); !ok {
		t.Fatal("base64 budget case")
	}
	if r := Encoding_Base64Decode(tctx, "QQ==", false, Some(int(1))); r.Failed {
		t.Fatal("padding is not counted against the budget")
	}
}

func TestBinary(t *testing.T) {
	be := NewBytes([]byte{0xff, 0xfe})
	if r := Binary_ReadInteger(tctx, be, 0, 2, true, false); r.Failed || r.Val != -2 {
		t.Fatalf("signed big endian: %v", r)
	}
	if r := Binary_ReadInteger(tctx, be, 0, 2, false, true); r.Failed || r.Val != 0xfeff {
		t.Fatalf("unsigned little endian: %v", r)
	}
	if r := Binary_ReadInteger(tctx, be, 1, 2, false, false); !r.Failed {
		t.Fatal("short read")
	}
	if r := Binary_ReadInteger(tctx, be, 0, 3, false, false); !r.Failed {
		t.Fatal("bad width")
	} else if _, ok := r.Err.(BinaryError_InvalidInput); !ok {
		t.Fatal("bad width case")
	}
	max := NewBytes([]byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff})
	if r := Binary_ReadInteger(tctx, max, 0, 8, false, false); !r.Failed {
		t.Fatal("unsigned 64-bit overflow")
	}
	if r := Binary_ReadInteger(tctx, max, 0, 8, true, false); r.Failed || r.Val != -1 {
		t.Fatal("signed 64-bit")
	}
	if r := Binary_WriteInteger(tctx, -2, 2, true, false); r.Failed || !reflect.DeepEqual(r.Val.Data, []byte{0xff, 0xfe}) {
		t.Fatalf("write signed: %v", r)
	}
	if r := Binary_WriteInteger(tctx, 0x0102, 2, false, true); r.Failed || !reflect.DeepEqual(r.Val.Data, []byte{2, 1}) {
		t.Fatalf("write little endian: %v", r)
	}
	for _, tt := range []struct {
		value, width int
		signed       bool
	}{{128, 1, true}, {-129, 1, true}, {256, 1, false}, {-1, 8, false}, {-1, 4, false}} {
		if r := Binary_WriteInteger(tctx, tt.value, tt.width, tt.signed, false); !r.Failed {
			t.Errorf("wrote %+v", tt)
		}
	}
	if r := Binary_WriteInteger(tctx, math.MaxInt64, 8, false, false); r.Failed {
		t.Fatal("max unsigned 64")
	}
	written := Binary_WriteFloat(tctx, 1.5, true)
	if r := Binary_ReadFloat(tctx, written, 0, true); r.Failed || r.Val != 1.5 {
		t.Fatalf("float round trip: %v", r)
	}
	if r := Binary_ReadFloat(tctx, written, 1, true); !r.Failed {
		t.Fatal("short float")
	}
}

func TestRegex(t *testing.T) {
	if r := Regex_Compile(tctx, "("); !r.Failed {
		t.Fatal("bad pattern")
	}
	re := Regex_Compile(tctx, `a+`).Val
	if !Regex_Matches(tctx, re, "baab") || Regex_Matches(tctx, re, "bbb") {
		t.Fatal("matches")
	}
	if r := Regex_FindAll(tctx, re, "a aa aaa", None[int]()); r.Failed || !reflect.DeepEqual(r.Val.Items, []string{"a", "aa", "aaa"}) {
		t.Fatalf("find_all %v", r)
	}
	if r := Regex_FindAll(tctx, re, "a aa aaa", Some(int(3))); r.Failed {
		t.Fatal("exact cap")
	}
	if r := Regex_FindAll(tctx, re, "a aa aaa", Some(int(2))); !r.Failed {
		t.Fatal("cap exceeded")
	} else if _, ok := r.Err.(RegexError_LimitExceeded); !ok {
		t.Fatal("cap case")
	}
	if r := Regex_FindAll(tctx, re, "b", Some(int(0))); r.Failed || len(r.Val.Items) != 0 {
		t.Fatalf("zero cap without matches: %v", r)
	}
	if r := Regex_FindAll(tctx, re, "a", Some(int(-1))); !r.Failed {
		t.Fatal("negative cap")
	}
	if r := Regex_ReplaceAll(tctx, re, "xaay", "<>", None[int]()); r.Failed || r.Val != "x<>y" {
		t.Fatalf("replace_all %v", r)
	}
	if r := Regex_ReplaceAll(tctx, re, "xaay", "<$0>", None[int]()); r.Val != "x<$0>y" {
		t.Fatal("replacement is literal")
	}
	if r := Regex_ReplaceAll(tctx, re, "xaay", "<>", Some(int(3))); !r.Failed {
		t.Fatal("replace budget")
	}
	if r := Regex_ReplaceAll(tctx, re, "xaay", "<>", Some(int(4))); r.Failed {
		t.Fatal("exact replace budget")
	}
}
