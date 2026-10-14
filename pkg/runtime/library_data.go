package msruntime

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"

	"math"
	"math/big"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

type libraryBigInt struct{ n *big.Int }
type libraryRegex struct{ pattern *regexp.Regexp }

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	add := libraryAdd
	for name, f := range map[string]func(float64) float64{"abs": math.Abs, "floor": math.Floor, "ceil": math.Ceil, "round": javascriptRound, "sqrt": math.Sqrt, "exp": math.Exp, "log": math.Log, "log2": math.Log2, "log10": math.Log10, "sin": math.Sin, "cos": math.Cos, "tan": math.Tan, "asin": math.Asin, "acos": math.Acos, "atan": math.Atan, "sinh": math.Sinh, "cosh": math.Cosh, "tanh": math.Tanh, "truncate": math.Trunc} {
		add("math", name, "Float", []LibraryParam{p("value", "Float")}, func(_ *Execution, _ string, a []Value) Value { return f(a[0].(float64)) })
	}
	for name, f := range map[string]func(float64, float64) float64{"pow": math.Pow, "min": math.Min, "max": math.Max, "hypot": math.Hypot, "atan2": math.Atan2, "remainder": math.Mod} {
		labels := []LibraryParam{p("left", "Float"), p("right", "Float")}
		if name == "pow" {
			labels = []LibraryParam{p("base", "Float"), p("exponent", "Float")}
		}
		if name == "atan2" {
			labels = []LibraryParam{p("y", "Float"), p("x", "Float")}
		}
		add("math", name, "Float", labels, func(_ *Execution, _ string, a []Value) Value { return f(a[0].(float64), a[1].(float64)) })
	}
	add("math", "is_nan", "Bool", []LibraryParam{p("value", "Float")}, func(_ *Execution, _ string, a []Value) Value { return math.IsNaN(a[0].(float64)) })
	add("math", "is_finite", "Bool", []LibraryParam{p("value", "Float")}, func(_ *Execution, _ string, a []Value) Value {
		v := a[0].(float64)
		return !math.IsNaN(v) && !math.IsInf(v, 0)
	})
	for name, value := range map[string]float64{"pi": math.Pi, "e": math.E} {
		add("math", name, "Float", nil, func(_ *Execution, _ string, _ []Value) Value { return value })
	}
	add("math", "abs_int", "Int", []LibraryParam{p("value", "Int")}, func(_ *Execution, _ string, a []Value) Value {
		n := a[0].(int64)
		if n == math.MinInt64 {
			return Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
		}
		if n < 0 {
			n = -n
		}
		return n
	})
	for name, f := range map[string]func(string) string{"trim": strings.TrimSpace, "upper": libraryUpper, "lower": libraryLower} {
		add("string", name, "String", []LibraryParam{p("text", "String")}, func(_ *Execution, _ string, a []Value) Value { return f(a[0].(string)) })
	}
	for name, f := range map[string]func(string, string) bool{"contains": strings.Contains, "starts_with": strings.HasPrefix, "ends_with": strings.HasSuffix} {
		label := "value"
		if name == "starts_with" {
			label = "prefix"
		}
		if name == "ends_with" {
			label = "suffix"
		}
		add("string", name, "Bool", []LibraryParam{p("value", "String"), p(label, "String")}, func(_ *Execution, _ string, a []Value) Value { return f(a[0].(string), a[1].(string)) })
	}
	add("string", "split", "List[String]", []LibraryParam{p("text", "String"), p("separator", "String"), p("max_parts", "Optional[Int]")}, func(_ *Execution, _ string, a []Value) Value {
		n := a[2].(int64)
		if n < 0 {
			return Panic("split requires nonnegative max_parts; pass 0 or a positive count")
		}
		if n == 0 {
			return libraryStrings(nil)
		}
		if n > int64(len(a[0].(string)))+1 {
			n = int64(len(a[0].(string))) + 1
		}
		parts := strings.Split(a[0].(string), a[1].(string))
		if int64(len(parts)) > n {
			parts = parts[:n]
		}
		return libraryStrings(parts)
	})
	add("string", "join", "String", []LibraryParam{p("parts", "List[String]"), p("separator", "String")}, func(_ *Execution, _ string, a []Value) Value {
		return strings.Join(libraryStringValues(a[0]), a[1].(string))
	})
	add("string", "replace", "String", []LibraryParam{p("text", "String"), p("old", "String"), p("new", "String"), p("max_replacements", "Optional[Int]")}, func(_ *Execution, _ string, a []Value) Value {
		n := a[3].(int64)
		if n < 0 {
			return Panic("invalid replacement bounds")
		}
		bound := int64(len(a[0].(string)))
		if a[1].(string) == "" {
			bound = int64(utf8.RuneCountInString(a[0].(string))) + 1
		}
		if n > bound {
			n = bound
		}
		return strings.Replace(a[0].(string), a[1].(string), a[2].(string), int(n))
	})
	libraryAlias("string", "replace_first", "replace")
	// A required count has its own ABI shape, while the prepared legacy body
	// retains explicit-cap normalization, bounds faults and scalar matching.
	replace := libraryFunctions["string/replace"].Body
	add("string", "replace_n", "String", []LibraryParam{p("text", "String"), p("old", "String"), p("new", "String"), p("max_replacements", "Int")}, func(ctx *Execution, result string, args []Value) Value {
		// The legacy option validator rejects a negative explicit Some. Raw
		// required Ints otherwise reach the primitive's different fault path.
		return replace(ctx, result, []Value{args[0], args[1], args[2], optional("Int", args[3], true)})
	})
	add("string", "scalar_values", "List[Int]", []LibraryParam{p("text", "String")}, func(ctx *Execution, _ string, a []Value) Value {
		var items []Value
		for i, r := range a[0].(string) {
			if i%4096 == 0 {
				CheckCancelled(ctx)
			}
			items = append(items, int64(r))
		}
		return libraryList("Int", items)
	})
	add("string", "from_scalars", libraryResult("String", "StringError"), []LibraryParam{p("values", "List[Int]")}, func(ctx *Execution, result string, a []Value) Value {
		var b strings.Builder
		for i, v := range a[0].(*List).Capture().Values() {
			if i%4096 == 0 {
				CheckCancelled(ctx)
			}
			n := v.(int64)
			if n < 0 || n > utf8.MaxRune || n >= 0xD800 && n <= 0xDFFF {
				return libraryError(result, "InvalidInput", "")
			}
			b.WriteRune(rune(n))
		}
		return libraryOK(result, b.String())
	})
	add("string", "slice_scalars", libraryResult("String", "StringError"), []LibraryParam{p("text", "String"), p("start", "Int"), p("end", "Int")}, func(_ *Execution, result string, a []Value) Value {
		r := []rune(a[0].(string))
		s, e := a[1].(int64), a[2].(int64)
		if s < 0 || e < s || e > int64(len(r)) {
			return libraryError(result, "OutOfRange", "")
		}
		return libraryOK(result, string(r[s:e]))
	})
	add("string", "scalar_length", "Int", []LibraryParam{p("text", "String")}, func(_ *Execution, _ string, a []Value) Value { return scalarCount(a[0].(string)) })
	add("encoding", "hex_encode", "String", []LibraryParam{p("data", "Bytes")}, func(_ *Execution, _ string, a []Value) Value { return hex.EncodeToString(a[0].(Bytes).Items) })
	add("encoding", "hex_decode", libraryResult("Bytes", "EncodingError"), []LibraryParam{p("text", "String"), p("max_bytes", "Optional[Int]")}, func(_ *Execution, result string, a []Value) Value {
		n := a[1].(int64)
		if v := libraryBound(result, n); v != nil {
			return v
		}
		text := a[0].(string)
		if int64(len(text)/2) > n {
			return libraryError(result, "LimitExceeded", "")
		}
		b, err := hex.DecodeString(text)
		if err != nil {
			return libraryError(result, "InvalidData", "")
		}
		return libraryOK(result, Bytes{b})
	})
	add("encoding", "base64_encode", "String", []LibraryParam{p("data", "Bytes"), p("url_safe", "Bool")}, func(_ *Execution, _ string, a []Value) Value {
		enc := base64.StdEncoding
		if a[1].(bool) {
			enc = base64.URLEncoding
		}
		return enc.EncodeToString(a[0].(Bytes).Items)
	})
	add("encoding", "base64_decode", libraryResult("Bytes", "EncodingError"), []LibraryParam{p("text", "String"), p("url_safe", "Bool"), p("max_bytes", "Optional[Int]")}, func(_ *Execution, result string, a []Value) Value {
		text := a[0].(string)
		n := a[2].(int64)
		if v := libraryBound(result, n); v != nil {
			return v
		}
		if strings.ContainsAny(text, "\r\n\t ") {
			return libraryError(result, "InvalidData", "")
		}
		padding := len(text) - len(strings.TrimRight(text, "="))
		if padding > 2 || len(text)%4 != 0 {
			return libraryError(result, "InvalidData", "")
		}
		if int64(len(text)/4)*3-int64(padding) > n {
			return libraryError(result, "LimitExceeded", "")
		}
		enc := base64.StdEncoding
		if a[1].(bool) {
			enc = base64.URLEncoding
		}
		b, err := enc.Strict().DecodeString(text)
		if err != nil {
			return libraryError(result, "InvalidData", "")
		}
		if int64(len(b)) > n {
			return libraryError(result, "LimitExceeded", "")
		}
		return libraryOK(result, Bytes{b})
	})
	add("bytes", "slice", libraryResult("Bytes", "CollectionError"), []LibraryParam{p("data", "Bytes"), p("start", "Int"), p("end", "Int")}, func(_ *Execution, r string, a []Value) Value {
		b := a[0].(Bytes).Items
		s, e, ok := librarySliceBounds(len(b), a[1].(int64), a[2].(int64))
		if !ok {
			return libraryError(r, "OutOfRange", "")
		}
		// Bytes are immutable, so the slice shares storage; the capacity limit keeps appends from touching the parent.
		return libraryOK(r, Bytes{b[s:e:e]})
	})
	add("bytes", "values", "List[Int]", []LibraryParam{p("data", "Bytes")}, func(_ *Execution, _ string, a []Value) Value {
		b := a[0].(Bytes).Items
		out := make([]Value, len(b))
		for i, v := range b {
			out[i] = int64(v)
		}
		return libraryList("Int", out)
	})
	add("bytes", "contains", "Bool", []LibraryParam{p("data", "Bytes"), p("value", "Bytes")}, func(_ *Execution, _ string, a []Value) Value {
		return bytes.Contains(a[0].(Bytes).Items, a[1].(Bytes).Items)
	})
	add("numbers", "parse_int", libraryResult("Int", "NumberError"), []LibraryParam{p("text", "String"), p("radix", "Int")}, func(_ *Execution, r string, a []Value) Value {
		radix := a[1].(int64)
		if radix < 2 || radix > 36 {
			return libraryError(r, "InvalidInput", "")
		}
		text := a[0].(string)
		if !libraryIntegerSyntax(text, int(radix)) {
			return libraryError(r, "InvalidData", "")
		}
		n, err := strconv.ParseInt(text, int(radix), 64)
		if err != nil {
			return libraryError(r, "OutOfRange", "")
		}
		return libraryOK(r, n)
	})
	add("numbers", "format_int", "String", []LibraryParam{p("value", "Int"), p("radix", "Int")}, func(_ *Execution, _ string, a []Value) Value {
		r := a[1].(int64)
		if r < 2 || r > 36 {
			return libraryRangeFault("Int.to_string", "radix", r, 2, 36)
		}
		return strconv.FormatInt(a[0].(int64), int(r))
	})
	add("numbers", "parse_float", libraryResult("Float", "NumberError"), []LibraryParam{p("text", "String")}, func(_ *Execution, r string, a []Value) Value {
		text := a[0].(string)
		if !libraryFloatSyntax.MatchString(text) && text != "NaN" && text != "Infinity" && text != "-Infinity" {
			return libraryError(r, "InvalidData", "")
		}
		n, err := strconv.ParseFloat(text, 64)
		if err != nil {
			return libraryError(r, "OutOfRange", "")
		}
		return libraryOK(r, n)
	})
	add("numbers", "format_float", "String", []LibraryParam{p("value", "Float")}, func(_ *Execution, _ string, a []Value) Value { return formatFloat(a[0].(float64)) })
	add("bigint", "from_int", "BigInt", []LibraryParam{p("value", "Int")}, func(_ *Execution, _ string, a []Value) Value { return libraryBigInt{big.NewInt(a[0].(int64))} })
	add("bigint", "parse", libraryResult("BigInt", "BigIntError"), []LibraryParam{p("text", "String"), p("radix", "Int"), p("max_digits", "Optional[Int]")}, func(_ *Execution, r string, a []Value) Value {
		text := a[0].(string)
		radix, n := a[1].(int64), a[2].(int64)
		if radix < 2 || radix > 36 || n < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		digits := len(strings.TrimPrefix(strings.TrimPrefix(text, "+"), "-"))
		if int64(digits) > n {
			return libraryError(r, "LimitExceeded", "")
		}
		if !libraryIntegerSyntax(text, int(radix)) {
			return libraryError(r, "InvalidData", "")
		}
		v, ok := new(big.Int).SetString(text, int(radix))
		if !ok {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, libraryBigInt{v})
	})
	for name, f := range map[string]func(*big.Int, *big.Int, *big.Int) *big.Int{"add": (*big.Int).Add, "subtract": (*big.Int).Sub, "multiply": (*big.Int).Mul, "bit_and": (*big.Int).And, "bit_or": (*big.Int).Or, "bit_xor": (*big.Int).Xor} {
		add("bigint", name, "BigInt", []LibraryParam{p("left", "BigInt"), p("other", "BigInt")}, func(_ *Execution, _ string, a []Value) Value {
			return libraryBigInt{f(new(big.Int), a[0].(libraryBigInt).n, a[1].(libraryBigInt).n)}
		})
	}
	for _, name := range []string{"divide", "remainder"} {
		add("bigint", name, libraryResult("BigInt", "BigIntError"), []LibraryParam{p("left", "BigInt"), p("other", "BigInt")}, func(_ *Execution, r string, a []Value) Value {
			x, y := a[0].(libraryBigInt).n, a[1].(libraryBigInt).n
			if y.Sign() == 0 {
				return libraryError(r, "InvalidInput", "")
			}
			out := new(big.Int)
			if name == "divide" {
				out.Quo(x, y)
			} else {
				out.Rem(x, y)
			}
			return libraryOK(r, libraryBigInt{out})
		})
	}
	add("bigint", "compare", "Int", []LibraryParam{p("left", "BigInt"), p("other", "BigInt")}, func(_ *Execution, _ string, a []Value) Value {
		return int64(a[0].(libraryBigInt).n.Cmp(a[1].(libraryBigInt).n))
	})
	add("bigint", "format", "String", []LibraryParam{p("value", "BigInt"), p("radix", "Int")}, func(_ *Execution, _ string, a []Value) Value {
		n := a[1].(int64)
		if n < 2 || n > 36 {
			return libraryRangeFault("BigInt.to_string", "radix", n, 2, 36)
		}
		return a[0].(libraryBigInt).n.Text(int(n))
	})
	add("bigint", "to_int", "Optional[Int]", []LibraryParam{p("value", "BigInt")}, func(_ *Execution, _ string, a []Value) Value {
		n := a[0].(libraryBigInt).n
		return optional("Int", n.Int64(), n.IsInt64())
	})
	add("binary", "read_integer", libraryResult("Int", "BinaryError"), []LibraryParam{p("data", "Bytes"), p("offset", "Int"), p("width", "Int"), p("signed", "Bool"), p("little_endian", "Bool")}, libraryReadInteger)
	add("binary", "write_integer", libraryResult("Bytes", "BinaryError"), []LibraryParam{p("value", "Int"), p("width", "Int"), p("signed", "Bool"), p("little_endian", "Bool")}, libraryWriteInteger)
	add("binary", "read_float", libraryResult("Float", "BinaryError"), []LibraryParam{p("data", "Bytes"), p("offset", "Int"), p("little_endian", "Bool")}, func(_ *Execution, r string, a []Value) Value {
		b := a[0].(Bytes).Items
		offset := a[1].(int64)
		if offset < 0 || offset > int64(len(b))-8 {
			return libraryError(r, "OutOfRange", "")
		}
		return libraryOK(r, math.Float64frombits(libraryOrder(a[2]).Uint64(b[offset:offset+8])))
	})
	add("binary", "write_float", "Bytes", []LibraryParam{p("value", "Float"), p("little_endian", "Bool")}, func(_ *Execution, _ string, a []Value) Value {
		b := make([]byte, 8)
		libraryOrder(a[1]).PutUint64(b, math.Float64bits(a[0].(float64)))
		return Bytes{b}
	})
	add("regex", "compile", libraryResult("Regex", "RegexError"), []LibraryParam{p("pattern", "String")}, func(_ *Execution, r string, a []Value) Value {
		re, err := regexp.Compile(a[0].(string))
		if err != nil {
			return libraryError(r, "InvalidData", "")
		}
		return libraryOK(r, libraryRegex{re})
	})
	add("regex", "matches", "Bool", []LibraryParam{p("pattern", "Regex"), p("text", "String")}, func(_ *Execution, _ string, a []Value) Value {
		return a[0].(libraryRegex).pattern.MatchString(a[1].(string))
	})
	add("regex", "find_all", libraryResult("List[String]", "RegexError"), []LibraryParam{p("pattern", "Regex"), p("text", "String"), p("max_matches", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		n := a[2].(int64)
		if n < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		text := a[1].(string)
		if n > int64(len(text))+1 {
			n = int64(len(text)) + 1
		}
		matches := a[0].(libraryRegex).pattern.FindAllString(text, int(n)+1)
		CheckCancelled(ctx)
		if int64(len(matches)) > n {
			return libraryError(r, "LimitExceeded", "")
		}
		return libraryOK(r, libraryStrings(matches))
	})
	// Sequential generic collection helpers retain the caller's actual list identity.
	variable := []LibraryParam{p("T", "")}
	libraryGeneric("collections", "reverse_in_place", "List[T]", variable, []LibraryParam{p("values", "List[T]")}, func(_ *Execution, _ string, a []Value) Value {
		v := a[0].(*List)
		v.reverse()
		return v
	})
	reverse := libraryFunctions["collections/reverse_in_place"].Body
	libraryGeneric("collections", "reversed", "List[T]", variable, []LibraryParam{p("values", "List[T]")}, func(ctx *Execution, result string, a []Value) Value {
		return reverse(ctx, result, []Value{Clone(a[0])})
	})
	libraryGeneric("collections", "slice", libraryResult("List[T]", "CollectionError"), variable, []LibraryParam{p("values", "List[T]"), p("start", "Int"), p("end", "Int")}, func(_ *Execution, r string, a []Value) Value {
		v := a[0].(*List)
		s, e, ok := librarySliceBounds(v.Len(), a[1].(int64), a[2].(int64))
		if !ok {
			return libraryError(r, "OutOfRange", "")
		}
		return libraryOK(r, v.CopySlice(int(s), int(e)))
	})
	for _, name := range []string{"take", "drop"} {
		libraryGeneric("collections", name, "List[T]", variable, []LibraryParam{p("values", "List[T]"), p("count", "Int")}, func(ctx *Execution, _ string, args []Value) Value {
			values := args[0].(*List)
			count := args[1].(int64)
			if count < 0 {
				return Panic("List." + name + ": count must be nonnegative, found " + strconv.FormatInt(count, 10))
			}
			source := values.Capture()
			if count > int64(source.Len()) {
				count = int64(source.Len())
			}
			start, end := 0, int(count)
			if name == "drop" {
				start, end = int(count), source.Len()
			}
			return values.copySliceChecked(ctx, start, end)
		})
	}
}

var libraryFloatSyntax = regexp.MustCompile(`^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$`)

func libraryIntegerSyntax(text string, radix int) bool {
	if text == "" {
		return false
	}
	if text[0] == '+' || text[0] == '-' {
		text = text[1:]
	}
	if text == "" {
		return false
	}
	for _, r := range text {
		n := -1
		if r >= '0' && r <= '9' {
			n = int(r - '0')
		} else if r >= 'a' && r <= 'z' {
			n = int(r-'a') + 10
		} else if r >= 'A' && r <= 'Z' {
			n = int(r-'A') + 10
		}
		if n < 0 || n >= radix {
			return false
		}
	}
	return true
}
func libraryOrder(v Value) binary.ByteOrder {
	if v.(bool) {
		return binary.LittleEndian
	}
	return binary.BigEndian
}
func libraryReadInteger(_ *Execution, r string, a []Value) Value {
	b := a[0].(Bytes).Items
	o, w := a[1].(int64), a[2].(int64)
	if w != 1 && w != 2 && w != 4 && w != 8 {
		return libraryError(r, "InvalidInput", "")
	}
	if o < 0 || o > int64(len(b))-w {
		return libraryError(r, "OutOfRange", "")
	}
	var n uint64
	chunk := b[o : o+w]
	if a[4].(bool) {
		for i := len(chunk) - 1; i >= 0; i-- {
			n = n<<8 | uint64(chunk[i])
		}
	} else {
		for _, v := range chunk {
			n = n<<8 | uint64(v)
		}
	}
	if a[3].(bool) && w < 8 && n&(uint64(1)<<(w*8-1)) != 0 {
		n |= ^uint64(0) << (w * 8)
	}
	if !a[3].(bool) && n > math.MaxInt64 {
		return libraryError(r, "OutOfRange", "")
	}
	return libraryOK(r, int64(n))
}
func libraryWriteInteger(_ *Execution, r string, a []Value) Value {
	n, w := a[0].(int64), a[1].(int64)
	if w != 1 && w != 2 && w != 4 && w != 8 {
		return libraryError(r, "InvalidInput", "")
	}
	signed := a[2].(bool)
	if !signed && n < 0 || w < 8 && (signed && (n < -(int64(1)<<(w*8-1)) || n >= (int64(1)<<(w*8-1))) || !signed && uint64(n) >= (uint64(1)<<(w*8))) {
		return libraryError(r, "OutOfRange", "")
	}
	b := make([]byte, w)
	v := uint64(n)
	for i := range b {
		at := i
		if !a[3].(bool) {
			at = len(b) - 1 - i
		}
		b[at] = byte(v)
		v >>= 8
	}
	return libraryOK(r, Bytes{b})
}

func javascriptRound(value float64) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) || value == 0 {
		return value
	}
	lower := math.Floor(value)
	if value-lower >= 0.5 {
		lower++
	}
	if lower == 0 {
		return math.Copysign(0, value)
	}
	return lower
}

// Full Unicode case mapping, independent of locale: ß becomes SS, ligatures
// expand, final sigma lowers to ς, and İ lowers to i + U+0307.
func libraryUpper(text string) string { return cases.Upper(language.Und).String(text) }
func libraryLower(text string) string { return cases.Lower(language.Und).String(text) }
