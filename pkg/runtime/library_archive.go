package msruntime

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"io"
	"path"
	"strings"
	"time"
	"unicode/utf8"
)

func init() {
	p := func(n, t string) LibraryParam { return LibraryParam{n, t} }
	libraryAdd("archive", "pack", libraryResult("Bytes", "ArchiveError"), []LibraryParam{p("entries", "List[ArchiveEntry]"), p("format", "String"), p("max_bytes", "Optional[Int64]")}, libraryArchivePack)
	libraryAdd("archive", "unpack", libraryResult("List[ArchiveEntry]", "ArchiveError"), []LibraryParam{p("data", "Bytes"), p("format", "String"), p("limits", "Optional[ArchiveLimits]")}, libraryArchiveUnpack)
}
func libraryArchivePath(s string, directory bool) bool {
	if s == "" || !utf8.ValidString(s) || strings.ContainsAny(s, "\\:\x00") || strings.HasPrefix(s, "/") {
		return false
	}
	if directory {
		s = strings.TrimSuffix(s, "/")
	} else if strings.HasSuffix(s, "/") {
		return false
	}
	for _, part := range strings.Split(s, "/") {
		if part == "" || part == "." || part == ".." {
			return false
		}
	}
	return true
}
func libraryArchivePack(ctx *Execution, r string, a []Value) Value {
	max := a[2].(int64)
	if max < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	entries := a[0].(*List).Items
	seen := map[string]bool{}
	for _, v := range entries {
		CheckCancelled(ctx)
		f := v.(Record).Fields
		s := f["path"].(string)
		directory := f["directory"].(bool)
		if !libraryArchivePath(s, directory) || directory && len(f["data"].(Bytes).Items) != 0 {
			return libraryError(r, "InvalidInput", "")
		}
		key := path.Clean(s)
		if seen[key] {
			return libraryError(r, "InvalidData", "")
		}
		seen[key] = true
	}
	w := &libraryLimitedWriter{max: max}
	switch a[1].(string) {
	case "tar":
		writer := tar.NewWriter(w)
		defer writer.Close()
		for _, v := range entries {
			CheckCancelled(ctx)
			f := v.(Record).Fields
			s := f["path"].(string)
			b := f["data"].(Bytes).Items
			header := &tar.Header{Name: s, Mode: 0600, Size: int64(len(b)), ModTime: time.Unix(0, 0), Format: tar.FormatPAX}
			if f["directory"].(bool) {
				header.Typeflag = tar.TypeDir
				header.Mode = 0700
				header.Name = strings.TrimSuffix(s, "/") + "/"
			}
			if err := writer.WriteHeader(header); err != nil {
				return libraryError(r, "LimitExceeded", "")
			}
			for len(b) > 0 {
				CheckCancelled(ctx)
				n := len(b)
				if n > 65536 {
					n = 65536
				}
				if _, err := writer.Write(b[:n]); err != nil {
					return libraryError(r, "LimitExceeded", "")
				}
				b = b[n:]
			}
		}
		if err := writer.Close(); err != nil {
			return libraryError(r, "LimitExceeded", "")
		}
	case "zip":
		writer := zip.NewWriter(w)
		defer writer.Close()
		for _, v := range entries {
			CheckCancelled(ctx)
			f := v.(Record).Fields
			header := &zip.FileHeader{Name: f["path"].(string), Method: zip.Deflate}
			header.Modified = time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC)
			header.SetMode(0600)
			if f["directory"].(bool) {
				header.Name = strings.TrimSuffix(header.Name, "/") + "/"
				header.Method = zip.Store
				header.SetMode(0700 | 1<<31)
			}
			entry, err := writer.CreateHeader(header)
			if err != nil {
				return libraryError(r, "LimitExceeded", "")
			}
			b := f["data"].(Bytes).Items
			for len(b) > 0 {
				CheckCancelled(ctx)
				n := len(b)
				if n > 65536 {
					n = 65536
				}
				if _, err = entry.Write(b[:n]); err != nil {
					return libraryError(r, "LimitExceeded", "")
				}
				b = b[n:]
			}
		}
		if err := writer.Close(); err != nil {
			return libraryError(r, "LimitExceeded", "")
		}
	default:
		return libraryError(r, "Unsupported", "")
	}
	return libraryOK(r, Bytes{append([]byte{}, w.Bytes()...)})
}
func libraryArchiveUnpack(ctx *Execution, r string, a []Value) Value {
	f := a[2].(Record).Fields
	count, entryMax, total := f["max_entries"].(int64), f["max_entry_bytes"].(int64), f["max_total_bytes"].(int64)
	if count < 0 || entryMax < 0 || total < 0 {
		return libraryError(r, "InvalidInput", "")
	}
	var out []Value
	seen := map[string]bool{}
	add := func(name string, directory bool, size int64, reader io.Reader) string {
		CheckCancelled(ctx)
		if !libraryArchivePath(name, directory) {
			return "InvalidData"
		}
		key := path.Clean(name)
		if seen[key] {
			return "InvalidData"
		}
		seen[key] = true
		if int64(len(out)) >= count || size > entryMax || size > total {
			return "LimitExceeded"
		}
		limit := entryMax
		if total < limit {
			limit = total
		}
		data, code := libraryReadBounded(ctx, reader, limit)
		if code != "" {
			return code
		}
		if directory && len(data) != 0 {
			return "InvalidData"
		}
		total -= int64(len(data))
		out = append(out, Record{"@std/ArchiveEntry", map[string]Value{"path": name, "directory": directory, "data": Bytes{data}}})
		return ""
	}
	data := a[0].(Bytes).Items
	switch a[1].(string) {
	case "tar":
		reader := tar.NewReader(bytes.NewReader(data))
		for {
			CheckCancelled(ctx)
			header, err := reader.Next()
			if err == io.EOF {
				break
			}
			if err != nil {
				return libraryError(r, "InvalidData", "")
			}
			if header.Typeflag != tar.TypeReg && header.Typeflag != 0 /* legacy regular-file encoding */ && header.Typeflag != tar.TypeDir {
				return libraryError(r, "Unsupported", "")
			}
			if code := add(header.Name, header.Typeflag == tar.TypeDir, header.Size, reader); code != "" {
				return libraryError(r, code, "")
			}
		}
	case "zip":
		reader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
		if err != nil {
			return libraryError(r, "InvalidData", "")
		}
		if int64(len(reader.File)) > count {
			return libraryError(r, "LimitExceeded", "")
		}
		for _, file := range reader.File {
			CheckCancelled(ctx)
			if file.NonUTF8 || !file.Mode().IsRegular() && !file.Mode().IsDir() {
				return libraryError(r, "Unsupported", "")
			}
			if file.UncompressedSize64 > uint64(entryMax) || file.UncompressedSize64 > uint64(total) {
				return libraryError(r, "LimitExceeded", "")
			}
			entry, err := file.Open()
			if err != nil {
				return libraryError(r, "InvalidData", "")
			}
			code := add(file.Name, file.FileInfo().IsDir(), int64(file.UncompressedSize64), entry)
			closeErr := entry.Close()
			if code != "" {
				return libraryError(r, code, "")
			}
			if closeErr != nil {
				return libraryError(r, "InvalidData", "")
			}
		}
	default:
		return libraryError(r, "Unsupported", "")
	}
	return libraryOK(r, libraryList("@std/ArchiveEntry", out))
}
