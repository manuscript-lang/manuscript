package msruntime

import (
	"context"
	"math"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"testing"
)

var tctx = RootExecution()

func okString(t *testing.T, r Result[string, StringError]) string {
	t.Helper()
	if r.Failed {
		t.Fatalf("unexpected failure %#v", r.Err)
	}
	return r.Val
}

func TestScalarOffsetCacheMatchesFreshScan(t *testing.T) {
	text := strings.Repeat("aé€😀", 600)
	runes := []rune(text)
	for _, n := range []int{0, 5, 5, 3, 1000, 1001, 2399, 7, 2399} {
		got := String_At(tctx, text, int(n))
		if !got.Some || got.Val != string(runes[n]) {
			t.Fatalf("scalar %d: got %v, want %q", n, got, string(runes[n]))
		}
	}
	if String_At(tctx, text, 2400).Some {
		t.Fatal("past the end")
	}
	if got := String_At(tctx, text, -1); got.Val != "😀" {
		t.Fatalf("relative index: %v", got)
	}
}

func TestScalarOffsetCacheConcurrentTexts(t *testing.T) {
	for i, unit := range []string{"aé€😀", "🙂xyz", "λ\xffé", "界é"} {
		t.Run(strconv.Itoa(i), func(t *testing.T) {
			t.Parallel()
			text := strings.Repeat(unit, 600)
			runes := []rune(text)
			for step := 0; step < 2000; step++ {
				n := (step * 977) % len(runes)
				index := n
				if step%2 == 0 {
					index -= len(runes)
				}
				if got := String_ScalarAt(tctx, text, index); !got.Some || got.Val != int(runes[n]) {
					t.Fatalf("scalar %d: got %v, want %U", index, got, runes[n])
				}
			}
		})
	}
}

func TestStringBasics(t *testing.T) {
	if String_Length(tctx, "aé😀") != 3 || String_ByteLength(tctx, "aé😀") != 7 {
		t.Fatal("length")
	}
	if got := String_Reverse(tctx, "aé😀"); got != "😀éa" {
		t.Fatal(got)
	}
	if got := String_Lines(tctx, "a\r\nb\n\nc\rd\n").Items; !reflect.DeepEqual(got, []string{"a", "b", "", "c\rd"}) {
		t.Fatalf("lines %q", got)
	}
	if got := String_Lines(tctx, "").Items; got == nil || len(got) != 0 {
		t.Fatalf("empty lines %v", got)
	}
	if got := String_Split(tctx, "a,b,c", ",", Some(int(2))).Items; !reflect.DeepEqual(got, []string{"a", "b"}) {
		t.Fatalf("split cap %q", got)
	}
	if got := String_Split(tctx, "", ",", None[int]()).Items; !reflect.DeepEqual(got, []string{""}) {
		t.Fatalf("split empty %q", got)
	}
	if got := String_Split(tctx, "aé", "", None[int]()).Items; !reflect.DeepEqual(got, []string{"a", "é"}) {
		t.Fatalf("split scalars %q", got)
	}
	if len(String_Split(tctx, "a,b", ",", Some(int(0))).Items) != 0 {
		t.Fatal("split zero")
	}
	if got := faultMessage(func() { String_Split(tctx, "a", ",", Some(int(-7))) }); got != "split: max_parts must be nonnegative, found -7" {
		t.Fatalf("split fault %q", got)
	}
	if String_IndexOf(tctx, "éé😀", "😀").Val != 2 || String_LastIndexOf(tctx, "aa", "").Val != 2 || String_IndexOf(tctx, "a", "b").Some {
		t.Fatal("index_of")
	}
	if got := String_ParseInt(tctx, "+12"); got != Some(int(12)) {
		t.Fatal(got)
	}
	for _, bad := range []string{"", "+", "1_0", " 1", "9223372036854775808"} {
		if String_ParseInt(tctx, bad).Some {
			t.Errorf("parsed %q", bad)
		}
	}
	if String_Upper(tctx, "straße") != "STRASSE" || String_Lower(tctx, "ΌΣ") != "ός" {
		t.Fatal("case mapping")
	}
	if String_Trim(tctx, "  a\n") != "a" || String_TrimStart(tctx, "  a ") != "a " || String_TrimEnd(tctx, " a  ") != " a" {
		t.Fatal("trim")
	}
}

func TestStringSplitLimitsMatchTruncatedFullSplit(t *testing.T) {
	for _, text := range []string{"", "a", "a,,b,", "aé🙂z", "aaaaa", "\xffa\xfe", strings.Repeat("field,", 1024)} {
		for _, separator := range []string{"", ",", "aa", "é", "missing"} {
			full := strings.Split(text, separator)
			for _, limit := range []int{0, 1, 2, 3, len(text), len(text) + 1, math.MaxInt} {
				got := String_Split(tctx, text, separator, Some(limit)).Items
				want := full[:min(limit, len(full))]
				if !slices.Equal(got, want) {
					t.Fatalf("split(%q, %q, %d) = %q, want %q", text, separator, limit, got, want)
				}
			}
		}
	}
	first := String_Split(tctx, "a,b,c", ",", Some(2))
	second := String_Split(tctx, "a,b,c", ",", Some(2))
	first.Items[0] = "changed"
	if second.Items[0] != "a" {
		t.Fatal("split results share mutable outer storage")
	}
}

func TestStringReplaceCaps(t *testing.T) {
	for _, tt := range []struct {
		text, old, new string
		n              int
		want           string
	}{
		{"aaaa", "a", "b", 0, "aaaa"}, {"aaaa", "a", "b", 2, "bbaa"}, {"aaaa", "a", "b", 999, "bbbb"},
		{"aaa", "a", "aa", 2, "aaaaa"}, {"é😀", "", "|", 2, "|é|😀"}, {"é😀", "", "|", 99, "|é|😀|"},
		{"", "", "x", 5, "x"}, {"abc", "b", "$1", 2, "a$1c"},
	} {
		if got := String_ReplaceN(tctx, tt.text, tt.old, tt.new, tt.n); got != tt.want {
			t.Errorf("replace_n(%q,%q,%q,%d) = %q, want %q", tt.text, tt.old, tt.new, tt.n, got, tt.want)
		}
	}
	if String_Replace(tctx, "aaaa", "a", "b", None[int]()) != "baaa" || String_ReplaceFirst(tctx, "aaaa", "a", "b", Some(int(2))) != "bbaa" {
		t.Fatal("compatibility names")
	}
	if got := faultMessage(func() { String_ReplaceN(tctx, "a", "a", "b", -3) }); got != "replace: max_replacements must be nonnegative, found -3" {
		t.Fatalf("fault %q", got)
	}
}

func TestStringSlicesAndScalars(t *testing.T) {
	if okString(t, String_Slice(tctx, "aé😀z", 1, -1)) != "é😀" {
		t.Fatal("slice")
	}
	if r := String_Slice(tctx, "abc", 2, 1); !r.Failed {
		t.Fatal("inverted slice")
	} else if _, ok := r.Err.(StringError_OutOfRange); !ok {
		t.Fatal(r.Err)
	}
	if r := String_SliceScalars(tctx, "abc", -1, 2); !r.Failed {
		t.Fatal("negative strict slice")
	}
	if okString(t, String_SliceScalars(tctx, "aé😀", 1, 3)) != "é😀" {
		t.Fatal("slice_scalars")
	}
	values := String_ScalarValues(tctx, "a😀")
	if !reflect.DeepEqual(values.Items, []int{97, 0x1F600}) {
		t.Fatal(values.Items)
	}
	if okString(t, String_FromScalars(tctx, values)) != "a😀" {
		t.Fatal("from_scalars")
	}
	for _, bad := range []int{-1, 0xD800, 0x110000} {
		if !String_FromScalars(tctx, NewList(bad)).Failed {
			t.Errorf("accepted scalar %d", bad)
		}
	}
	if String_ScalarAt(tctx, "a😀", -1) != Some(int(0x1F600)) {
		t.Fatal("scalar_at")
	}
}

func TestStringBudgets(t *testing.T) {
	if r := String_Repeat(tctx, "ab", 3, Some(int(5))); !r.Failed {
		t.Fatal("repeat over budget")
	}
	if okString(t, String_Repeat(tctx, "ab", 3, Some(int(6)))) != "ababab" || okString(t, String_Repeat(tctx, "", math.MaxInt64, None[int]())) != "" {
		t.Fatal("repeat")
	}
	if r := String_Repeat(tctx, "a", -1, None[int]()); !r.Failed {
		t.Fatal("negative count")
	}
	if okString(t, String_PadStart(tctx, "7", 3, "ab", None[int]())) != "aba7" && okString(t, String_PadStart(tctx, "7", 3, "ab", None[int]())) != "ab7" {
		t.Fatal("pad_start")
	}
	if got := okString(t, String_PadEnd(tctx, "é", 4, "xy", None[int]())); got != "éxyx" {
		t.Fatalf("pad_end %q", got)
	}
	if r := String_PadEnd(tctx, "a", 10, "x", Some(int(5))); !r.Failed {
		t.Fatal("pad budget")
	}
	if got := okString(t, String_ReplaceAll(tctx, "a-b-c", "-", "+", Some(int(5)))); got != "a+b+c" {
		t.Fatal(got)
	}
	if r := String_ReplaceAll(tctx, "a-b-c", "-", "++", Some(int(5))); !r.Failed {
		t.Fatal("replace_all budget")
	}
	if got := okString(t, String_ReplaceAll(tctx, "ab", "", "|", None[int]())); got != "|a|b|" {
		t.Fatal(got)
	}
	if got := okString(t, String_Normalize(tctx, "é", "NFC", None[int]())); got != "é" {
		t.Fatal("normalize")
	}
	if r := String_Normalize(tctx, "e", "nfc", None[int]()); !r.Failed {
		t.Fatal("form spelling is case sensitive")
	}
	if r := String_Normalize(tctx, "éé", "NFD", Some(int(3))); !r.Failed {
		t.Fatal("normalize budget")
	}
	if got := okString(t, NormalizationForm_Normalize(tctx, NormalizationForm_Nfkc{}, "ﬁ", None[int]())); got != "fi" {
		t.Fatal("nfkc")
	}
}

func TestStringCancellation(t *testing.T) {
	ctx := RootExecution()
	cancelCtx, cancel := context.WithCancel(ctx.Context)
	cancel()
	ctx.Context = cancelCtx
	defer func() {
		if _, ok := recover().(cancelled); !ok {
			t.Fatal("cancelled normalize did not unwind")
		}
	}()
	String_Normalize(ctx, "text", "NFC", None[int]())
}

func TestStringBuilder(t *testing.T) {
	b := NewStringBuilder()
	StringBuilder_Append(tctx, b, "a")
	StringBuilder_Append(tctx, b, "é")
	first := StringBuilder_Freeze(tctx, b)
	if first != "aé" || StringBuilder_Freeze(tctx, b) != first {
		t.Fatal("freeze")
	}
	if got := faultMessage(func() { StringBuilder_Append(tctx, b, "x") }); got != "builder is sealed" {
		t.Fatalf("sealed fault %q", got)
	}
}

func TestErrorMessages(t *testing.T) {
	if Errors_Message_StringError(tctx, StringError_Failed{Message: "boom"}) != "boom" || Errors_Message_StringError(tctx, StringError_OutOfRange{}) != "string: value out of range" {
		t.Fatal("string")
	}
	if Errors_Message_NumberError(tctx, NumberError_InvalidData{}) != "number: invalid data" ||
		Errors_Message_BigIntError(tctx, BigIntError_LimitExceeded{}) != "big integer: limit exceeded" ||
		Errors_Message_EncodingError(tctx, EncodingError_InvalidInput{}) != "encoding: invalid input" ||
		Errors_Message_BinaryError(tctx, BinaryError_OutOfRange{}) != "binary: value out of range" ||
		Errors_Message_RegexError(tctx, RegexError_InvalidData{}) != "regular expression: invalid data" {
		t.Fatal("domain messages")
	}
}
