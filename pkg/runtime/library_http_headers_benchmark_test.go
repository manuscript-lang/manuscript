//go:build !ms_lean

package msruntime

import (
	"fmt"
	"net/http"
	"testing"
)

var httpBenchmarkValue Value

func BenchmarkHTTPHeaders(b *testing.B) {
	host := http.Header{}
	for i := 0; i < 16; i++ {
		host.Add(fmt.Sprintf("X-Field-%d", i), "first")
		host.Add(fmt.Sprintf("X-Field-%d", i), "second")
	}
	host.Add("Set-Cookie", "a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT")
	host.Add("Set-Cookie", "b=2")
	headers := libraryHTTPHeaders(host)
	for _, name := range []string{"x-field-8", "X-FIELD-8"} {
		b.Run("shared_lookup/"+name, func(b *testing.B) {
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				values, _ := headers.values(name)
				httpBenchmarkValue = values
			}
		})
	}
	b.Run("explicit_membership_clone", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			httpBenchmarkValue = headers.clone()
		}
	})
	b.Run("proxy_metadata_cached_headers", func(b *testing.B) {
		response := Record{"@std/ClientResponse", map[string]Value{"head": Record{"@std/HttpResponseMetadata", map[string]Value{"status": int64(200), "headers": headers}}, "body": Bytes{}}}
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			httpBenchmarkValue = libraryResponseMetadata(response)
		}
	})
	b.Run("proxy_reconvert_headers_control", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			httpBenchmarkValue = libraryHTTPHeaders(host)
		}
	})
	b.Run("explicit_text", func(b *testing.B) {
		spec := libraryFunctions["http/headers_text"]
		ctx := RootExecution()
		args := []Value{headers, "x-field-8"}
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			httpBenchmarkValue = invokeLibrary(spec, ctx, libraryRuntimeType(spec.Result), args)
		}
	})
}
