package msruntime

import (
	"bytes"
	"golang.org/x/text/unicode/norm"
	"io"
	"math"
	"strconv"
	"strings"
	"sync/atomic"
	"unicode"
	"unicode/utf8"
	"unsafe"
)

// StringAt is the direct path for String.at calls.
func StringAt(ctx *Execution, text, index Value, result string) Value {
	CheckCancelled(ctx)
	return stringScalarAt(text.(string), index.(int64), result, false)
}

func stringScalarAt(text string, index int64, result string, asInt bool) Value {
	ascii := isASCII(text)
	count := len(text)
	if !ascii {
		count = utf8.RuneCountInString(text)
	}
	i := relativeIndex(count, index)
	if i < 0 || i >= int64(count) {
		return Alternative{Type: result, Tag: "none"}
	}
	var scalar rune
	if ascii {
		scalar = rune(text[i])
	} else {
		scalar, _ = utf8.DecodeRuneInString(text[scalarOffset(text, int(i)):])
	}
	var value Value = string(scalar)
	if asInt {
		value = int64(scalar)
	}
	return Alternative{result, "some", []Value{value}}
}

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	add := libraryAdd
	add("string", "length", "Int", []LibraryParam{p("text", "String")}, func(_ *Execution, _ string, args []Value) Value {
		return scalarCount(args[0].(string))
	})
	add("string", "is_empty", "Bool", []LibraryParam{p("text", "String")}, func(_ *Execution, _ string, args []Value) Value {
		return len(args[0].(string)) == 0
	})
	add("string", "compare", "Int", []LibraryParam{p("text", "String"), p("other", "String")}, func(_ *Execution, _ string, args []Value) Value {
		return int64(strings.Compare(args[0].(string), args[1].(string)))
	})
	add("string", "chars", "List[String]", []LibraryParam{p("text", "String")}, func(ctx *Execution, result string, args []Value) Value {
		var items []Value
		count := 0
		for _, scalar := range args[0].(string) {
			if count%1024 == 0 {
				CheckCancelled(ctx)
			}
			items = append(items, string(scalar))
			count++
		}
		return NewList(result, items)
	})
	add("string", "reverse", "String", []LibraryParam{p("text", "String")}, func(ctx *Execution, _ string, args []Value) Value {
		remaining := args[0].(string)
		var out strings.Builder
		out.Grow(len(remaining))
		for count := 0; len(remaining) > 0; count++ {
			if count%1024 == 0 {
				CheckCancelled(ctx)
			}
			scalar, width := utf8.DecodeLastRuneInString(remaining)
			out.WriteRune(scalar)
			remaining = remaining[:len(remaining)-width]
		}
		return out.String()
	})
	add("string", "lines", "List[String]", []LibraryParam{p("text", "String")}, func(ctx *Execution, result string, args []Value) Value {
		text := args[0].(string)
		var items []Value
		start := 0
		for i := 0; i < len(text); i++ {
			if i%4096 == 0 {
				CheckCancelled(ctx)
			}
			if text[i] != '\n' {
				continue
			}
			end := i
			if end > start && text[end-1] == '\r' {
				end--
			}
			items = append(items, text[start:end])
			start = i + 1
		}
		if start < len(text) {
			items = append(items, text[start:])
		}
		return NewList(result, items)
	})
	for _, spec := range []struct {
		name, label string
		format      byte
		minimum     int64
	}{
		{"format_fixed", "digits", 'f', 0}, {"format_exponential", "digits", 'e', 0}, {"format_precision", "precision", 'g', 1},
	} {
		add("numbers", spec.name, libraryResult("String", "NumberError"), []LibraryParam{p("value", "Float"), p(spec.label, "Int")}, func(_ *Execution, r string, a []Value) Value {
			precision := a[1].(int64)
			if precision < spec.minimum || precision > 100 {
				return libraryError(r, "InvalidInput", "")
			}
			return libraryOK(r, formatFloatPrecision(a[0].(float64), spec.format, int(precision)))
		})
	}

	add("string", "concat", "String", []LibraryParam{p("text", "String"), p("values", "String")}, func(_ *Execution, _ string, a []Value) Value { return a[0].(string) + a[1].(string) })
	add("string", "normalize", libraryResult("String", "StringError"), []LibraryParam{p("text", "String"), p("form", "String"), p("max_bytes", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		max := a[2].(int64)
		if max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		var form norm.Form
		switch a[1].(string) {
		case "NFC":
			form = norm.NFC
		case "NFD":
			form = norm.NFD
		case "NFKC":
			form = norm.NFKC
		case "NFKD":
			form = norm.NFKD
		default:
			return libraryError(r, "InvalidInput", "")
		}
		reader := form.Reader(strings.NewReader(a[0].(string)))
		var out strings.Builder
		var chunk [4096]byte
		for {
			CheckCancelled(ctx)
			n, err := reader.Read(chunk[:])
			if int64(n) > max-int64(out.Len()) {
				return libraryError(r, "LimitExceeded", "")
			}
			out.Write(chunk[:n])
			if err == io.EOF {
				break
			}
			if err != nil {
				return libraryError(r, "InvalidData", "")
			}
		}
		return libraryOK(r, out.String())
	})

	for _, name := range []string{"at", "scalar_at"} {
		result := "Optional[String]"
		if name == "scalar_at" {
			result = "Optional[Int]"
		}
		add("string", name, result, []LibraryParam{p("text", "String"), p("index", "Int")}, func(_ *Execution, r string, a []Value) Value {
			return stringScalarAt(a[0].(string), a[1].(int64), r, name == "scalar_at")
		})
	}
	for _, name := range []string{"index_of", "last_index_of"} {
		add("string", name, "Optional[Int]", []LibraryParam{p("text", "String"), p("value", "String")}, func(_ *Execution, r string, a []Value) Value {
			text, value := a[0].(string), a[1].(string)
			i := strings.Index(text, value)
			if name == "last_index_of" {
				i = strings.LastIndex(text, value)
			}
			if i < 0 {
				return Alternative{Type: r, Tag: "none"}
			}
			return Alternative{r, "some", []Value{int64(utf8.RuneCountInString(text[:i]))}}
		})
	}
	for _, name := range []string{"trim_start", "trim_end"} {
		add("string", name, "String", []LibraryParam{p("text", "String")}, func(_ *Execution, _ string, a []Value) Value {
			if name == "trim_start" {
				return strings.TrimLeftFunc(a[0].(string), unicode.IsSpace)
			}
			return strings.TrimRightFunc(a[0].(string), unicode.IsSpace)
		})
	}
	add("string", "slice", libraryResult("String", "StringError"), []LibraryParam{p("text", "String"), p("start", "Int"), p("end", "Int")}, func(_ *Execution, r string, a []Value) Value {
		text := a[0].(string)
		ascii := isASCII(text)
		count := len(text)
		if !ascii {
			count = utf8.RuneCountInString(text)
		}
		s, e, ok := librarySliceBounds(count, a[1].(int64), a[2].(int64))
		if !ok {
			return libraryError(r, "OutOfRange", "")
		}
		if ascii {
			return libraryOK(r, text[s:e])
		}
		start := scalarOffset(text, int(s))
		return libraryOK(r, text[start:start+scalarOffset(text[start:], int(e-s))])
	})
	for _, name := range []string{"pad_start", "pad_end"} {
		add("string", name, libraryResult("String", "StringError"), []LibraryParam{p("text", "String"), p("target_length", "Int"), p("padding", "String"), p("max_bytes", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
			text, padding := a[0].(string), a[2].(string)
			target, max := a[1].(int64), a[3].(int64)
			if target < 0 || max < 0 {
				return libraryError(r, "InvalidInput", "")
			}
			max = min(max, nativeMaxBytes)
			if int64(len(text)) > max {
				return libraryError(r, "LimitExceeded", "")
			}
			needed := target - int64(utf8.RuneCountInString(text))
			if needed <= 0 || padding == "" {
				return libraryOK(r, text)
			}
			// Each scalar occupies at least one byte; reject excessive targets before work.
			if needed > max-int64(len(text)) {
				return libraryError(r, "LimitExceeded", "")
			}
			count := int64(utf8.RuneCountInString(padding))
			cycles, remainder := needed/count, needed%count
			prefixEnd := 0
			if remainder > 0 {
				seen := int64(0)
				prefixEnd = len(padding)
				for i := range padding {
					if seen == remainder {
						prefixEnd = i
						break
					}
					seen++
				}
			}
			remaining := max - int64(len(text)) - int64(prefixEnd)
			if remaining < 0 || cycles > remaining/int64(len(padding)) {
				return libraryError(r, "LimitExceeded", "")
			}
			var b strings.Builder
			if name == "pad_end" {
				b.WriteString(text)
			}
			for i := int64(0); i < cycles; i++ {
				CheckCancelled(ctx)
				b.WriteString(padding)
			}
			b.WriteString(padding[:prefixEnd])
			if name == "pad_start" {
				b.WriteString(text)
			}
			return libraryOK(r, b.String())
		})
	}
	add("string", "replace_all", libraryResult("String", "StringError"), []LibraryParam{p("text", "String"), p("old", "String"), p("new", "String"), p("max_bytes", "Optional[Int]")}, func(ctx *Execution, r string, a []Value) Value {
		text, old, replacement, max := a[0].(string), a[1].(string), a[2].(string), a[3].(int64)
		if max < 0 {
			return libraryError(r, "InvalidInput", "")
		}
		var b strings.Builder
		write := func(s string) bool {
			if int64(len(s)) > max-int64(b.Len()) {
				return false
			}
			b.WriteString(s)
			return true
		}
		if old == "" {
			if !write(replacement) {
				return libraryError(r, "LimitExceeded", "")
			}
			for _, scalar := range text {
				CheckCancelled(ctx)
				if !write(string(scalar)) || !write(replacement) {
					return libraryError(r, "LimitExceeded", "")
				}
			}
		} else {
			for {
				CheckCancelled(ctx)
				i := strings.Index(text, old)
				if i < 0 {
					if !write(text) {
						return libraryError(r, "LimitExceeded", "")
					}
					break
				}
				if !write(text[:i]) || !write(replacement) {
					return libraryError(r, "LimitExceeded", "")
				}
				text = text[i+len(old):]
			}
		}
		return libraryOK(r, b.String())
	})
	add("bytes", "at", "Optional[Int]", []LibraryParam{p("data", "Bytes"), p("index", "Int")}, func(_ *Execution, r string, a []Value) Value {
		items := a[0].(Bytes).Items
		i := relativeIndex(len(items), a[1].(int64))
		if i < 0 || i >= int64(len(items)) {
			return Alternative{Type: r, Tag: "none"}
		}
		return Alternative{r, "some", []Value{int64(items[i])}}
	})
	for _, name := range []string{"index_of", "last_index_of", "starts_with", "ends_with"} {
		result := "Optional[Int]"
		if name == "starts_with" || name == "ends_with" {
			result = "Bool"
		}
		add("bytes", name, result, []LibraryParam{p("data", "Bytes"), p("value", "Bytes")}, func(_ *Execution, r string, a []Value) Value {
			data, value := a[0].(Bytes).Items, a[1].(Bytes).Items
			if name == "starts_with" {
				return bytes.HasPrefix(data, value)
			}
			if name == "ends_with" {
				return bytes.HasSuffix(data, value)
			}
			i := bytes.Index(data, value)
			if name == "last_index_of" {
				i = bytes.LastIndex(data, value)
			}
			if i < 0 {
				return Alternative{Type: r, Tag: "none"}
			}
			return Alternative{r, "some", []Value{int64(i)}}
		})
	}
	add("bytes", "reverse", "Bytes", []LibraryParam{p("data", "Bytes")}, func(ctx *Execution, _ string, a []Value) Value {
		out := append([]byte{}, a[0].(Bytes).Items...)
		for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
			CheckCancelled(ctx)
			out[i], out[j] = out[j], out[i]
		}
		return Bytes{out}
	})
	libraryAlias("bytes", "reversed", "reverse")
	add("bytes", "with_value", "Bytes", []LibraryParam{p("data", "Bytes"), p("index", "Int"), p("value", "Int")}, func(_ *Execution, _ string, a []Value) Value {
		items := a[0].(Bytes).Items
		i, n := relativeIndex(len(items), a[1].(int64)), a[2].(int64)
		if i < 0 || i >= int64(len(items)) {
			return libraryIndexFault("Bytes.with_value", len(items), a[1].(int64))
		}
		if n < 0 || n > 255 {
			return libraryRangeFault("Bytes.with_value", "value", n, 0, 255)
		}
		out := append([]byte{}, items...)
		out[i] = byte(n)
		return Bytes{out}
	})
	add("bytes", "is_empty", "Bool", []LibraryParam{p("data", "Bytes")}, func(_ *Execution, _ string, a []Value) Value { return len(a[0].(Bytes).Items) == 0 })
	add("bytes", "split", "List[Bytes]", []LibraryParam{p("data", "Bytes"), p("separator", "Bytes"), p("max_parts", "Optional[Int]")}, libraryBytesSplit)
}

func libraryBytesSplit(ctx *Execution, result string, args []Value) Value {
	data, separator := args[0].(Bytes).Items, args[1].(Bytes).Items
	limit := args[2].(int64)
	if limit < 0 {
		return Panic("split: max_parts must be nonnegative, found " + strconv.FormatInt(limit, 10))
	}
	out := NewList(result, nil)
	if len(separator) == 0 {
		for i := 0; i < len(data) && int64(len(out.Items)) < limit; i++ {
			if i%1024 == 0 {
				CheckCancelled(ctx)
			}
			out.Items = append(out.Items, Bytes{data[i : i+1]})
		}
		return out
	}
	start := 0
	for int64(len(out.Items)) < limit {
		CheckCancelled(ctx)
		offset := bytes.Index(data[start:], separator)
		CheckCancelled(ctx)
		if offset < 0 {
			out.Items = append(out.Items, Bytes{data[start:]})
			break
		}
		end := start + offset
		out.Items = append(out.Items, Bytes{data[start:end]})
		start = end + len(separator)
	}
	return out
}

// Precision formatting preserves requested trailing digits. Manuscript uses the
// existing binary64 ties-to-even rounding and preserves signed zero.
func formatFloatPrecision(value float64, format byte, precision int) string {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return formatFloat(value)
	}
	if format == 'f' {
		if math.Abs(value) >= 1e21 {
			return formatFloat(value)
		}
		return strconv.FormatFloat(value, 'f', precision, 64)
	}
	digits := precision
	if format == 'g' {
		digits = precision - 1
	}
	scientific := strconv.FormatFloat(value, 'e', digits, 64)
	mantissa, exponent, _ := strings.Cut(scientific, "e")
	e, _ := strconv.Atoi(exponent)
	if format == 'g' && e >= -6 && e < precision {
		return strconv.FormatFloat(value, 'f', precision-e-1, 64)
	}
	sign := "+"
	if e < 0 {
		sign = ""
	}
	return mantissa + "e" + sign + strconv.Itoa(e)
}

func isASCII(text string) bool {
	for i := 0; i < len(text); i++ {
		if text[i] >= utf8.RuneSelf {
			return false
		}
	}
	return true
}

// scalarOffset returns the byte offset of the n-th scalar in text without allocating.
func scalarOffset(text string, n int) int {
	offset := 0
	for ; n > 0 && offset < len(text); n-- {
		_, width := utf8.DecodeRuneInString(text[offset:])
		offset += width
	}
	return offset
}

// scalarCountCache remembers the last long string measured, so a loop that
// calls scalar_length() every iteration pays for the scan once. It holds the
// string itself, which keeps its backing memory from being reused under the
// pointer comparison.
type scalarCountEntry struct {
	text  string
	count int64
}

var scalarCountCache atomic.Pointer[scalarCountEntry]

func scalarCount(text string) int64 {
	if len(text) < 1024 {
		return int64(utf8.RuneCountInString(text))
	}
	if e := scalarCountCache.Load(); e != nil && len(e.text) == len(text) && unsafe.StringData(e.text) == unsafe.StringData(text) {
		return e.count
	}
	n := int64(utf8.RuneCountInString(text))
	scalarCountCache.Store(&scalarCountEntry{text, n})
	return n
}
