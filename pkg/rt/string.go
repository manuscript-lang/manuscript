package rt

import (
	"io"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"unicode"
	"unicode/utf8"
	"unsafe"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
	"golang.org/x/text/unicode/norm"
)

// StringBuilder accumulates text. Freeze seals it; appending afterwards is a
// fault. All operations hold the builder's lock.
type StringBuilder struct {
	mu     sync.Mutex
	text   strings.Builder
	sealed bool
}

// NewStringBuilder returns an empty builder.
func NewStringBuilder() *StringBuilder { return &StringBuilder{} }

func StringBuilder_Append(ctx *Execution, b *StringBuilder, value string) Unit {
	CheckCancelled(ctx)
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.sealed {
		Raise("builder is sealed")
	}
	b.text.WriteString(value)
	return Unit{}
}

func StringBuilder_Freeze(ctx *Execution, b *StringBuilder) string {
	CheckCancelled(ctx)
	b.mu.Lock()
	defer b.mu.Unlock()
	b.sealed = true
	return b.text.String()
}

func Errors_Message_StringError(_ *Execution, e StringError) string {
	switch e := e.(type) {
	case StringError_Failed:
		return e.Message
	case StringError_InvalidInput:
		return "string: " + txInvalidInput
	case StringError_OutOfRange:
		return "string: " + txOutOfRange
	case StringError_LimitExceeded:
		return "string: " + txLimitExceeded
	}
	return "string: operation failed"
}

func stringFail[T any](e StringError) Result[T, StringError] { return Fail[T, StringError](e) }

// String_Length counts Unicode scalars.
func String_Length(_ *Execution, text string) int64 { return stringScalarCount(text) }

func String_ScalarLength(_ *Execution, text string) int64 { return stringScalarCount(text) }

func String_IsEmpty(_ *Execution, text string) bool { return len(text) == 0 }

func String_ByteLength(_ *Execution, text string) int64 { return int64(len(text)) }

func String_Chars(ctx *Execution, text string) *List[string] {
	items := make([]string, 0, len(text))
	for _, scalar := range text {
		if len(items)%1024 == 0 {
			CheckCancelled(ctx)
		}
		items = append(items, string(scalar))
	}
	return NewList(items...)
}

func String_Reverse(ctx *Execution, text string) string {
	var out strings.Builder
	out.Grow(len(text))
	for count := 0; len(text) > 0; count++ {
		if count%1024 == 0 {
			CheckCancelled(ctx)
		}
		scalar, width := utf8.DecodeLastRuneInString(text)
		out.WriteRune(scalar)
		text = text[:len(text)-width]
	}
	return out.String()
}

func String_Compare(_ *Execution, a, b string) int64 { return int64(strings.Compare(a, b)) }

func String_Lines(ctx *Execution, text string) *List[string] {
	items := []string{}
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
	return NewList(items...)
}

func normalizeText(ctx *Execution, form norm.Form, text string, maxBytes Option[int64]) Result[string, StringError] {
	max := txLimit(maxBytes)
	if max < 0 {
		return stringFail[string](StringError_InvalidInput{})
	}
	reader := form.Reader(strings.NewReader(text))
	var out strings.Builder
	var chunk [4096]byte
	for {
		CheckCancelled(ctx)
		n, err := reader.Read(chunk[:])
		if int64(n) > max-int64(out.Len()) {
			return stringFail[string](StringError_LimitExceeded{})
		}
		out.Write(chunk[:n])
		if err == io.EOF {
			break
		}
		if err != nil {
			return stringFail[string](StringError_Failed{Message: "string: normalization failed"})
		}
	}
	return Ok[string, StringError](out.String())
}

// String_Normalize takes the form's spelling: NFC, NFD, NFKC or NFKD.
func String_Normalize(ctx *Execution, text, form string, maxBytes Option[int64]) Result[string, StringError] {
	if txLimit(maxBytes) < 0 {
		return stringFail[string](StringError_InvalidInput{})
	}
	switch form {
	case "NFC":
		return normalizeText(ctx, norm.NFC, text, maxBytes)
	case "NFD":
		return normalizeText(ctx, norm.NFD, text, maxBytes)
	case "NFKC":
		return normalizeText(ctx, norm.NFKC, text, maxBytes)
	case "NFKD":
		return normalizeText(ctx, norm.NFKD, text, maxBytes)
	}
	return stringFail[string](StringError_InvalidInput{})
}

func NormalizationForm_Normalize(ctx *Execution, form NormalizationForm, text string, maxBytes Option[int64]) Result[string, StringError] {
	switch form.(type) {
	case NormalizationForm_Nfc:
		return normalizeText(ctx, norm.NFC, text, maxBytes)
	case NormalizationForm_Nfd:
		return normalizeText(ctx, norm.NFD, text, maxBytes)
	case NormalizationForm_Nfkc:
		return normalizeText(ctx, norm.NFKC, text, maxBytes)
	case NormalizationForm_Nfkd:
		return normalizeText(ctx, norm.NFKD, text, maxBytes)
	}
	return stringFail[string](StringError_InvalidInput{})
}

func String_Concat(_ *Execution, a, b string) string { return a + b }

func String_Contains(_ *Execution, text, value string) bool { return strings.Contains(text, value) }

func String_StartsWith(_ *Execution, text, prefix string) bool {
	return strings.HasPrefix(text, prefix)
}

func String_EndsWith(_ *Execution, text, suffix string) bool {
	return strings.HasSuffix(text, suffix)
}

func String_Trim(_ *Execution, text string) string { return strings.TrimSpace(text) }

func String_TrimStart(_ *Execution, text string) string {
	return strings.TrimLeftFunc(text, unicode.IsSpace)
}

func String_TrimEnd(_ *Execution, text string) string {
	return strings.TrimRightFunc(text, unicode.IsSpace)
}

// Full Unicode case mapping, independent of locale: the German sharp s becomes
// SS, ligatures expand, final sigma lowers to its final form.
func String_Upper(_ *Execution, text string) string { return cases.Upper(language.Und).String(text) }
func String_Lower(_ *Execution, text string) string { return cases.Lower(language.Und).String(text) }

func String_Repeat(_ *Execution, text string, count int64, maxBytes Option[int64]) Result[string, StringError] {
	max := txLimit(maxBytes)
	if count < 0 || max < 0 {
		return stringFail[string](StringError_InvalidInput{})
	}
	if len(text) == 0 {
		return Ok[string, StringError]("")
	}
	max = min(max, txMaxBytes)
	if count > max/int64(len(text)) {
		return stringFail[string](StringError_LimitExceeded{})
	}
	return Ok[string, StringError](strings.Repeat(text, int(count)))
}

func stringReplaceLimit(text, old, replacement string, n int64) string {
	if n < 0 {
		txFaultNegative("replace", "max_replacements", n)
	}
	bound := int64(len(text))
	if old == "" {
		bound = int64(utf8.RuneCountInString(text)) + 1
	}
	if n > bound {
		n = bound
	}
	return strings.Replace(text, old, replacement, int(n))
}

// String_ReplaceFirst replaces the first occurrence, or up to the supplied cap.
func String_ReplaceFirst(_ *Execution, text, old, replacement string, max Option[int64]) string {
	n := int64(1)
	if max.Some {
		n = max.Val
	}
	return stringReplaceLimit(text, old, replacement, n)
}

func String_Replace(ctx *Execution, text, old, replacement string, max Option[int64]) string {
	return String_ReplaceFirst(ctx, text, old, replacement, max)
}

func String_ReplaceN(_ *Execution, text, old, replacement string, max int64) string {
	return stringReplaceLimit(text, old, replacement, max)
}

func String_ScalarValues(ctx *Execution, text string) *List[int64] {
	items := make([]int64, 0, len(text))
	for i, r := range text {
		if i%4096 == 0 {
			CheckCancelled(ctx)
		}
		items = append(items, int64(r))
	}
	return NewList(items...)
}

func String_FromScalars(ctx *Execution, values *List[int64]) Result[string, StringError] {
	var b strings.Builder
	for i, n := range values.Items {
		if i%4096 == 0 {
			CheckCancelled(ctx)
		}
		if n < 0 || n > utf8.MaxRune || n >= 0xD800 && n <= 0xDFFF {
			return stringFail[string](StringError_InvalidInput{})
		}
		b.WriteRune(rune(n))
	}
	return Ok[string, StringError](b.String())
}

func String_SliceScalars(_ *Execution, text string, start, end int64) Result[string, StringError] {
	count, ascii := stringShape(text)
	if start < 0 || end < start || end > count {
		return stringFail[string](StringError_OutOfRange{})
	}
	if ascii {
		return Ok[string, StringError](text[start:end])
	}
	return Ok[string, StringError](text[scalarIndexOffset(text, int(start)):scalarIndexOffset(text, int(end))])
}

func String_Slice(_ *Execution, text string, start, end int64) Result[string, StringError] {
	count, ascii := stringShape(text)
	s, e, ok := txSliceBounds(int(count), start, end)
	if !ok {
		return stringFail[string](StringError_OutOfRange{})
	}
	if ascii {
		return Ok[string, StringError](text[s:e])
	}
	return Ok[string, StringError](text[scalarIndexOffset(text, int(s)):scalarIndexOffset(text, int(e))])
}

func String_Split(ctx *Execution, text, separator string, maxParts Option[int64]) *List[string] {
	n := txLimit(maxParts)
	if n < 0 {
		txFaultNegative("split", "max_parts", n)
	}
	if n == 0 {
		return NewList[string]()
	}
	if n > int64(len(text))+1 {
		n = int64(len(text)) + 1
	}
	parts := strings.Split(text, separator)
	if int64(len(parts)) > n {
		parts = parts[:n]
	}
	return NewList(parts...)
}

func String_At(_ *Execution, text string, index int64) Option[string] {
	scalar, ok := stringScalarAt(text, index)
	if !ok {
		return None[string]()
	}
	return Some(string(scalar))
}

func String_ScalarAt(_ *Execution, text string, index int64) Option[int64] {
	scalar, ok := stringScalarAt(text, index)
	if !ok {
		return None[int64]()
	}
	return Some(int64(scalar))
}

func stringScalarAt(text string, index int64) (rune, bool) {
	count, ascii := stringShape(text)
	i := txRelative(int(count), index)
	if i < 0 || i >= count {
		return 0, false
	}
	if ascii {
		return rune(text[i]), true
	}
	scalar, _ := utf8.DecodeRuneInString(text[scalarIndexOffset(text, int(i)):])
	return scalar, true
}

func String_IndexOf(_ *Execution, text, value string) Option[int64] {
	i := strings.Index(text, value)
	if i < 0 {
		return None[int64]()
	}
	return Some(int64(utf8.RuneCountInString(text[:i])))
}

func String_LastIndexOf(_ *Execution, text, value string) Option[int64] {
	i := strings.LastIndex(text, value)
	if i < 0 {
		return None[int64]()
	}
	return Some(int64(utf8.RuneCountInString(text[:i])))
}

func stringPad(ctx *Execution, atStart bool, text string, target int64, padding string, maxBytes Option[int64]) Result[string, StringError] {
	max := txLimit(maxBytes)
	if target < 0 || max < 0 {
		return stringFail[string](StringError_InvalidInput{})
	}
	max = min(max, txMaxBytes)
	if int64(len(text)) > max {
		return stringFail[string](StringError_LimitExceeded{})
	}
	needed := target - int64(utf8.RuneCountInString(text))
	if needed <= 0 || padding == "" {
		return Ok[string, StringError](text)
	}
	// Each scalar occupies at least one byte; reject excessive targets before work.
	if needed > max-int64(len(text)) {
		return stringFail[string](StringError_LimitExceeded{})
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
		return stringFail[string](StringError_LimitExceeded{})
	}
	var b strings.Builder
	if !atStart {
		b.WriteString(text)
	}
	for i := int64(0); i < cycles; i++ {
		CheckCancelled(ctx)
		b.WriteString(padding)
	}
	b.WriteString(padding[:prefixEnd])
	if atStart {
		b.WriteString(text)
	}
	return Ok[string, StringError](b.String())
}

func String_PadStart(ctx *Execution, text string, target int64, padding string, maxBytes Option[int64]) Result[string, StringError] {
	return stringPad(ctx, true, text, target, padding, maxBytes)
}

func String_PadEnd(ctx *Execution, text string, target int64, padding string, maxBytes Option[int64]) Result[string, StringError] {
	return stringPad(ctx, false, text, target, padding, maxBytes)
}

func String_ReplaceAll(ctx *Execution, text, old, replacement string, maxBytes Option[int64]) Result[string, StringError] {
	max := txLimit(maxBytes)
	if max < 0 {
		return stringFail[string](StringError_InvalidInput{})
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
			return stringFail[string](StringError_LimitExceeded{})
		}
		for _, scalar := range text {
			CheckCancelled(ctx)
			if !write(string(scalar)) || !write(replacement) {
				return stringFail[string](StringError_LimitExceeded{})
			}
		}
		return Ok[string, StringError](b.String())
	}
	for {
		CheckCancelled(ctx)
		i := strings.Index(text, old)
		if i < 0 {
			if !write(text) {
				return stringFail[string](StringError_LimitExceeded{})
			}
			break
		}
		if !write(text[:i]) || !write(replacement) {
			return stringFail[string](StringError_LimitExceeded{})
		}
		text = text[i+len(old):]
	}
	return Ok[string, StringError](b.String())
}

func String_ToBytes(_ *Execution, text string) *Bytes { return NewBytes([]byte(text)) }

// String_ParseInt parses signed ASCII decimal digits; anything else,
// including overflow, is none.
func String_ParseInt(_ *Execution, text string) Option[int64] {
	start := 0
	if text != "" && (text[0] == '+' || text[0] == '-') {
		start = 1
	}
	if start == len(text) {
		return None[int64]()
	}
	for i := start; i < len(text); i++ {
		if text[i] < '0' || text[i] > '9' {
			return None[int64]()
		}
	}
	n, err := strconv.ParseInt(text, 10, 64)
	if err != nil {
		return None[int64]()
	}
	return Some(n)
}

func stringIsASCII(text string) bool {
	for i := 0; i < len(text); i++ {
		if text[i] >= utf8.RuneSelf {
			return false
		}
	}
	return true
}

// stringScalarOffset returns the byte offset of the n-th scalar without allocating.
func stringScalarOffset(text string, n int) int {
	offset := 0
	for ; n > 0 && offset < len(text); n-- {
		_, width := utf8.DecodeRuneInString(text[offset:])
		offset += width
	}
	return offset
}

// The shape cache remembers the last long string measured, so a loop that
// indexes, slices or measures the same text every iteration pays for the scans
// once. It holds the string itself, which keeps its backing memory from being
// reused under the pointer comparison. Entries are immutable; updates replace
// them.
const stringShapeCacheMin = 1024

type stringShapeEntry struct {
	text  string
	count int64
	ascii bool
}

var stringShapeCache atomic.Pointer[stringShapeEntry]

func stringSameText(a, b string) bool {
	return len(a) == len(b) && unsafe.StringData(a) == unsafe.StringData(b)
}

// stringShape returns the scalar count of text and whether it is all ASCII.
func stringShape(text string) (count int64, ascii bool) {
	if len(text) < stringShapeCacheMin {
		if ascii = stringIsASCII(text); ascii {
			return int64(len(text)), true
		}
		return int64(utf8.RuneCountInString(text)), false
	}
	if e := stringShapeCache.Load(); e != nil && stringSameText(e.text, text) {
		return e.count, e.ascii
	}
	e := &stringShapeEntry{text: text, ascii: stringIsASCII(text)}
	if e.ascii {
		e.count = int64(len(text))
	} else {
		e.count = int64(utf8.RuneCountInString(text))
	}
	stringShapeCache.Store(e)
	return e.count, e.ascii
}

func stringScalarCount(text string) int64 {
	count, _ := stringShape(text)
	return count
}

// stringScalarHint remembers the byte offset of one scalar index in the last
// long non-ASCII string, so sequential or nearby indexing walks a few scalars
// instead of rescanning from the start.
type stringScalarHint struct {
	text   string
	scalar int
	offset int
}

var stringScalarHintCache atomic.Pointer[stringScalarHint]

// scalarIndexOffset returns the byte offset of scalar n of text, which callers
// have checked lies within 0..scalar count.
func scalarIndexOffset(text string, n int) int {
	if len(text) < stringShapeCacheMin {
		return stringScalarOffset(text, n)
	}
	scalar, offset := 0, 0
	if h := stringScalarHintCache.Load(); h != nil && stringSameText(h.text, text) && txAbs(h.scalar-n) < n {
		scalar, offset = h.scalar, h.offset
	}
	for ; scalar < n && offset < len(text); scalar++ {
		_, width := utf8.DecodeRuneInString(text[offset:])
		offset += width
	}
	for ; scalar > n; scalar-- {
		_, width := utf8.DecodeLastRuneInString(text[:offset])
		offset -= width
	}
	stringScalarHintCache.Store(&stringScalarHint{text, scalar, offset})
	return offset
}

func txAbs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
