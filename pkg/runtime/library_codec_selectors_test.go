package msruntime

import (
	"context"
	"testing"
)

func TestTypedCodecReceiverIdentityAndCancellation(t *testing.T) {
	for _, test := range []struct {
		kind, tag, operation string
		args                 []Value
	}{
		{"HashAlgorithm", "Sha256", "digest", []Value{Bytes{}}},
		{"HashAlgorithm", "Sha256", "hmac", []Value{Bytes{}, Bytes{}}},
		{"CompressionFormat", "Gzip", "compress", []Value{Bytes{}, int64(6), optional("Int", nil, false)}},
		{"CompressionFormat", "Gzip", "decompress", []Value{Bytes{}, optional("Int", nil, false)}},
		{"ArchiveFormat", "Zip", "pack", []Value{libraryList("@std/ArchiveEntry", nil), optional("Int", nil, false)}},
		{"ArchiveFormat", "Zip", "unpack", []Value{Bytes{}, optional("@std/ArchiveLimits", nil, false)}},
		{"NormalizationForm", "Nfc", "normalize", []Value{"text", optional("Int", nil, false)}},
	} {
		t.Run(test.kind+"/"+test.operation, func(t *testing.T) {
			local := Alternative{Type: "local/" + test.kind, Tag: test.tag}
			if _, ok := nativeLibraryMember(local, test.operation, ""); ok {
				t.Fatal("local alternative acquired native operation")
			}
			receiver := Alternative{Type: "@std/" + test.kind, Tag: test.tag}
			bound, ok := nativeLibraryMember(receiver, test.operation, "")
			if !ok {
				t.Fatal("typed operation unavailable")
			}
			ctx := RootExecution()
			lifetime, cancel := context.WithCancel(ctx.Context)
			cancel()
			ctx.Context = lifetime
			fault := recovered(func() { bound.(Function).Body(ctx, test.args) })
			if _, ok := fault.(cancelled); !ok {
				t.Fatalf("cancelled selector continued: %v", fault)
			}
		})
	}
}
