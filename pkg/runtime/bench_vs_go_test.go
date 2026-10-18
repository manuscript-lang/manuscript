package msruntime

import (
	"strconv"
	"strings"
	"testing"
)

// Benchmarks compare the runtime collections and strings with plain Go. Run:
// go test ./pkg/runtime -run XXX -bench VsGo -benchmem
const vsGoN = 1000

func vsGoKeys() []string {
	keys := make([]string, vsGoN)
	for i := range keys {
		keys[i] = "key-" + strconv.Itoa(i*7919)
	}
	return keys
}

// ---- Map[string,int] vs Go map

func BenchmarkVsGoMapPutGo(b *testing.B) {
	keys := vsGoKeys()
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		m := map[string]int{}
		for i, k := range keys {
			m[k] = i
		}
	}
}

func BenchmarkVsGoMapPutMS(b *testing.B) {
	keys := vsGoKeys()
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		m := NewMap[string, int]()
		for i, k := range keys {
			m.Put(k, i)
		}
	}
}

func BenchmarkVsGoMapGetGo(b *testing.B) {
	keys := vsGoKeys()
	m := map[string]int{}
	for i, k := range keys {
		m[k] = i
	}
	b.ReportAllocs()
	b.ResetTimer()
	sum := 0
	for n := 0; n < b.N; n++ {
		for _, k := range keys {
			sum += m[k]
		}
	}
	_ = sum
}

func BenchmarkVsGoMapGetMS(b *testing.B) {
	keys := vsGoKeys()
	m := NewMap[string, int]()
	for i, k := range keys {
		m.Put(k, i)
	}
	b.ReportAllocs()
	b.ResetTimer()
	sum := 0
	for n := 0; n < b.N; n++ {
		for _, k := range keys {
			v, _ := m.Lookup(k)
			sum += v
		}
	}
	_ = sum
}

func BenchmarkVsGoMapReplaceGo(b *testing.B) {
	keys := vsGoKeys()
	m := map[string]int{}
	for i, k := range keys {
		m[k] = i
	}
	b.ReportAllocs()
	b.ResetTimer()
	for n := 0; n < b.N; n++ {
		for i, k := range keys {
			m[k] = i + n
		}
	}
}

func BenchmarkVsGoMapReplaceMS(b *testing.B) {
	keys := vsGoKeys()
	m := NewMap[string, int]()
	for i, k := range keys {
		m.Put(k, i)
	}
	b.ReportAllocs()
	b.ResetTimer()
	for n := 0; n < b.N; n++ {
		for i, k := range keys {
			m.Put(k, i+n)
		}
	}
}

func BenchmarkVsGoMapIterateGo(b *testing.B) {
	keys := vsGoKeys()
	m := map[string]int{}
	for i, k := range keys {
		m[k] = i
	}
	b.ReportAllocs()
	b.ResetTimer()
	sum := 0
	for n := 0; n < b.N; n++ {
		for _, v := range m {
			sum += v
		}
	}
	_ = sum
}

func BenchmarkVsGoMapIterateMS(b *testing.B) {
	keys := vsGoKeys()
	m := NewMap[string, int]()
	for i, k := range keys {
		m.Put(k, i)
	}
	b.ReportAllocs()
	b.ResetTimer()
	sum := 0
	for n := 0; n < b.N; n++ {
		for _, e := range m.Snapshot() {
			sum += e.Value
		}
	}
	_ = sum
}

func BenchmarkVsGoMapDeleteGo(b *testing.B) {
	keys := vsGoKeys()
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		b.StopTimer()
		m := map[string]int{}
		for i, k := range keys {
			m[k] = i
		}
		b.StartTimer()
		for _, k := range keys {
			delete(m, k)
		}
	}
}

func BenchmarkVsGoMapDeleteMS(b *testing.B) {
	keys := vsGoKeys()
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		b.StopTimer()
		m := NewMap[string, int]()
		for i, k := range keys {
			m.Put(k, i)
		}
		b.StartTimer()
		for _, k := range keys {
			m.Delete(k)
		}
	}
}

// Int keys, the common case for counters and indexes.
func BenchmarkVsGoIntMapPutGo(b *testing.B) {
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		m := map[int]int{}
		for i := 0; i < vsGoN; i++ {
			m[i*31] = i
		}
	}
}

func BenchmarkVsGoIntMapPutMS(b *testing.B) {
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		m := NewMap[int, int]()
		for i := 0; i < vsGoN; i++ {
			m.Put(i*31, i)
		}
	}
}

func BenchmarkVsGoIntMapGetGo(b *testing.B) {
	m := map[int]int{}
	for i := 0; i < vsGoN; i++ {
		m[i*31] = i
	}
	b.ReportAllocs()
	b.ResetTimer()
	sum := 0
	for n := 0; n < b.N; n++ {
		for i := 0; i < vsGoN; i++ {
			sum += m[i*31]
		}
	}
	_ = sum
}

func BenchmarkVsGoIntMapGetMS(b *testing.B) {
	m := NewMap[int, int]()
	for i := 0; i < vsGoN; i++ {
		m.Put(i*31, i)
	}
	b.ReportAllocs()
	b.ResetTimer()
	sum := 0
	for n := 0; n < b.N; n++ {
		for i := 0; i < vsGoN; i++ {
			v, _ := m.Lookup(i * 31)
			sum += v
		}
	}
	_ = sum
}

// ---- Set[int] vs Go map[int]struct{}

func BenchmarkVsGoSetAddGo(b *testing.B) {
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		s := map[int]struct{}{}
		for i := 0; i < vsGoN; i++ {
			s[i*31] = struct{}{}
		}
	}
}

func BenchmarkVsGoSetAddMS(b *testing.B) {
	b.ReportAllocs()
	for n := 0; n < b.N; n++ {
		s := NewSet[int]()
		for i := 0; i < vsGoN; i++ {
			s.Add(i * 31)
		}
	}
}

func BenchmarkVsGoSetHasGo(b *testing.B) {
	s := map[int]struct{}{}
	for i := 0; i < vsGoN; i++ {
		s[i*31] = struct{}{}
	}
	b.ReportAllocs()
	b.ResetTimer()
	c := 0
	for n := 0; n < b.N; n++ {
		for i := 0; i < vsGoN; i++ {
			if _, ok := s[i*31]; ok {
				c++
			}
		}
	}
	_ = c
}

func BenchmarkVsGoSetHasMS(b *testing.B) {
	s := NewSet[int]()
	for i := 0; i < vsGoN; i++ {
		s.Add(i * 31)
	}
	b.ReportAllocs()
	b.ResetTimer()
	c := 0
	for n := 0; n < b.N; n++ {
		for i := 0; i < vsGoN; i++ {
			if s.Has(i * 31) {
				c++
			}
		}
	}
	_ = c
}

// ---- String

var vsGoASCII = strings.Repeat("the quick brown fox jumps over the lazy dog ", 40) // ~1.7 KB
var vsGoUnicode = strings.Repeat("héllo wörld ünïcode tëxt ✓ ", 60)                // non-ASCII

func BenchmarkVsGoStringLengthASCII(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += String_Length(tctx, vsGoASCII)
	}
	_ = n
}

func BenchmarkVsGoStringLengthUnicode(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += String_Length(tctx, vsGoUnicode)
	}
	_ = n
}

func BenchmarkVsGoStringAtASCII(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		if o := String_At(tctx, vsGoASCII, i%1000); o.Some {
			n += len(o.Val)
		}
	}
	_ = n
}

func BenchmarkVsGoStringScalarAtUnicodeSequential(b *testing.B) {
	b.ReportAllocs()
	n := 0
	count := String_Length(tctx, vsGoUnicode)
	for i := 0; i < b.N; i++ {
		if o := String_ScalarAt(tctx, vsGoUnicode, i%count); o.Some {
			n += o.Val
		}
	}
	_ = n
}

func BenchmarkVsGoStringScalarAtUnicodeStrided(b *testing.B) {
	b.ReportAllocs()
	n := 0
	count := String_Length(tctx, vsGoUnicode)
	for i := 0; i < b.N; i++ {
		if o := String_ScalarAt(tctx, vsGoUnicode, (i*977)%count); o.Some {
			n += o.Val
		}
	}
	_ = n
}

func BenchmarkStringScalarAtUnicodeParallel(b *testing.B) {
	count := String_Length(tctx, vsGoUnicode)
	b.ReportAllocs()
	b.RunParallel(func(pb *testing.PB) {
		index := 0
		for pb.Next() {
			if !String_ScalarAt(tctx, vsGoUnicode, index%count).Some {
				b.Error("missing scalar")
				return
			}
			index++
		}
	})
}

func BenchmarkVsGoStringSliceASCII(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		r := String_Slice(tctx, vsGoASCII, 10, 200)
		n += len(r.Val)
	}
	_ = n
}

func BenchmarkVsGoStringSliceGo(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(vsGoASCII[10:200])
	}
	_ = n
}

func BenchmarkVsGoStringSliceUnicode(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		r := String_Slice(tctx, vsGoUnicode, 10, 200)
		n += len(r.Val)
	}
	_ = n
}

func BenchmarkVsGoStringContainsMS(b *testing.B) {
	b.ReportAllocs()
	c := 0
	for i := 0; i < b.N; i++ {
		if String_Contains(tctx, vsGoASCII, "lazy dog the") {
			c++
		}
	}
	_ = c
}

func BenchmarkVsGoStringContainsGo(b *testing.B) {
	b.ReportAllocs()
	c := 0
	for i := 0; i < b.N; i++ {
		if strings.Contains(vsGoASCII, "lazy dog the") {
			c++
		}
	}
	_ = c
}

func BenchmarkVsGoStringSplitMS(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(String_Split(tctx, vsGoASCII, " ", None[int]()).Items)
	}
	_ = n
}

func BenchmarkVsGoStringSplitGo(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(strings.Split(vsGoASCII, " "))
	}
	_ = n
}

func BenchmarkStringSplitLimited(b *testing.B) {
	// Use the same loop as the other VsGo cases: b.Loop suppresses inlining
	// here and would force the otherwise stack-local List wrapper to escape.
	for _, size := range []int{16, 65536} {
		text := strings.Repeat("field,", size)
		b.Run(strconv.Itoa(size), func(b *testing.B) {
			b.Run("MS", func(b *testing.B) {
				b.ReportAllocs()
				for i := 0; i < b.N; i++ {
					result := String_Split(tctx, text, ",", Some(2))
					if len(result.Items) != 2 || result.Items[1] != "field" {
						b.Fatal("incorrect split result")
					}
				}
			})
			b.Run("Go", func(b *testing.B) {
				b.ReportAllocs()
				for i := 0; i < b.N; i++ {
					result := strings.SplitN(text, ",", 3)
					if len(result) < 2 || result[1] != "field" {
						b.Fatal("incorrect split result")
					}
				}
			})
		})
	}
}

func BenchmarkVsGoStringUpperMS(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(String_Upper(tctx, vsGoASCII))
	}
	_ = n
}

func BenchmarkVsGoStringUpperGo(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(strings.ToUpper(vsGoASCII))
	}
	_ = n
}

func BenchmarkVsGoStringLowerMS(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(String_Lower(tctx, vsGoASCII))
	}
	_ = n
}

func BenchmarkVsGoStringLowerGo(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(strings.ToLower(vsGoASCII))
	}
	_ = n
}

func BenchmarkVsGoStringIndexOfASCII(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		if o := String_IndexOf(tctx, vsGoASCII, "dog the quick"); o.Some {
			n += o.Val
		}
	}
	_ = n
}

func BenchmarkVsGoStringIndexOfUnicode(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		if o := String_IndexOf(tctx, vsGoUnicode, "✓ héllo wörld ünï"); o.Some {
			n += o.Val
		}
	}
	_ = n
}

func BenchmarkVsGoStringCharsMS(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(String_Chars(tctx, vsGoASCII).Items)
	}
	_ = n
}

func BenchmarkVsGoStringReverseMS(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(String_Reverse(tctx, vsGoASCII))
	}
	_ = n
}

func BenchmarkVsGoStringConcatLoopMS(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		s := ""
		for j := 0; j < 200; j++ {
			s = String_Concat(tctx, s, "ab")
		}
	}
}

func BenchmarkVsGoStringReplaceMS(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(String_Replace(tctx, vsGoASCII, "the", "a", None[int]()))
	}
	_ = n
}

func BenchmarkVsGoStringReplaceGo(b *testing.B) {
	b.ReportAllocs()
	n := 0
	for i := 0; i < b.N; i++ {
		n += len(strings.ReplaceAll(vsGoASCII, "the", "a"))
	}
	_ = n
}
