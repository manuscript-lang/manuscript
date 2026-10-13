package msruntime

// Typed selector operations share the existing implementations. This keeps
// budgets, format completion, domain errors and cancellation on one path.
func init() {
	libraryAdd("string", "form_normalize", libraryResult("String", "StringError"), []LibraryParam{{"form", "NormalizationForm"}, {"text", "String"}, {"max_bytes", "Optional[Int]"}}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		name := librarySelectorName(args[0], "NormalizationForm")
		return invokeLibrary(libraryFunctions["string/normalize"], ctx, result, []Value{args[1], name, args[2]})
	})
	libraryAdd("crypto", "hash_algorithm_digest", "Bytes", []LibraryParam{{"algorithm", "HashAlgorithm"}, {"data", "Bytes"}}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		name := librarySelectorName(args[0], "HashAlgorithm")
		return invokeLibrary(libraryFunctions["crypto/"+name], ctx, result, args[1:])
	})
	libraryAdd("crypto", "hash_algorithm_hmac", libraryResult("Bytes", "CryptoError"), []LibraryParam{{"algorithm", "HashAlgorithm"}, {"key", "Bytes"}, {"data", "Bytes"}}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		name := librarySelectorName(args[0], "HashAlgorithm")
		return invokeLibrary(libraryFunctions["crypto/hmac"], ctx, result, []Value{args[1], args[2], name})
	})
	libraryAdd("compress", "format_compress", libraryResult("Bytes", "CompressionError"), []LibraryParam{{"format", "CompressionFormat"}, {"data", "Bytes"}, {"level", "Int"}, {"max_bytes", "Optional[Int64]"}}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		name := librarySelectorName(args[0], "CompressionFormat")
		return invokeLibrary(libraryFunctions["compress/compress"], ctx, result, []Value{args[1], name, args[2], args[3]})
	})
	libraryAdd("compress", "format_decompress", libraryResult("Bytes", "CompressionError"), []LibraryParam{{"format", "CompressionFormat"}, {"data", "Bytes"}, {"max_bytes", "Optional[Int64]"}}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		name := librarySelectorName(args[0], "CompressionFormat")
		return invokeLibrary(libraryFunctions["compress/decompress"], ctx, result, []Value{args[1], name, args[2]})
	})
	libraryAdd("archive", "format_pack", libraryResult("Bytes", "ArchiveError"), []LibraryParam{{"format", "ArchiveFormat"}, {"entries", "List[ArchiveEntry]"}, {"max_bytes", "Optional[Int64]"}}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		name := librarySelectorName(args[0], "ArchiveFormat")
		return invokeLibrary(libraryFunctions["archive/pack"], ctx, result, []Value{args[1], name, args[2]})
	})
	libraryAdd("archive", "format_unpack", libraryResult("List[ArchiveEntry]", "ArchiveError"), []LibraryParam{{"format", "ArchiveFormat"}, {"data", "Bytes"}, {"limits", "Optional[ArchiveLimits]"}}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		name := librarySelectorName(args[0], "ArchiveFormat")
		return invokeLibrary(libraryFunctions["archive/unpack"], ctx, result, []Value{args[1], name, args[2]})
	})
}

var librarySelectorNames = map[string]map[string]string{
	"HashAlgorithm":     {"Sha256": "sha256", "Sha384": "sha384", "Sha512": "sha512"},
	"CompressionFormat": {"Gzip": "gzip", "Zlib": "zlib", "Deflate": "deflate"},
	"ArchiveFormat":     {"Zip": "zip", "Tar": "tar"},
	"NormalizationForm": {"Nfc": "NFC", "Nfd": "NFD", "Nfkc": "NFKC", "Nfkd": "NFKD"},
}

func librarySelectorName(value Value, kind string) string {
	selector, ok := value.(Alternative)
	if !ok || selector.Type != "@std/"+kind || len(selector.Fields) != 0 {
		return Panic("invalid " + kind + " receiver").(string)
	}
	name := librarySelectorNames[kind][selector.Tag]
	if name == "" {
		return Panic("invalid " + kind + " case " + selector.Tag).(string)
	}
	return name
}
