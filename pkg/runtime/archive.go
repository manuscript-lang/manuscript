package msruntime

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"io"
	"math"
	"path"
	"strings"
	"time"
	"unicode/utf8"
)

func archiveFormatName(f ArchiveFormat) string {
	switch f.(type) {
	case ArchiveFormat_Zip:
		return "zip"
	case ArchiveFormat_Tar:
		return "tar"
	}
	Raise("invalid ArchiveFormat receiver")
	return ""
}

func archiveError(code string) ArchiveError {
	switch code {
	case "InvalidInput":
		return ArchiveError_InvalidInput{}
	case "InvalidData":
		return ArchiveError_InvalidData{}
	case "LimitExceeded":
		return ArchiveError_LimitExceeded{}
	case "Unsupported":
		return ArchiveError_Unsupported{}
	}
	return ArchiveError_Failed{Message: ""}
}

func archiveFail[T any](code string) Result[T, ArchiveError] {
	return Fail[T, ArchiveError](archiveError(code))
}

func archivePathValid(s string, directory bool) bool {
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

// archiveConflict reports whether a regular file shares a normalized path with
// an ancestor directory of another entry (file "a" with "a/b").
func archiveConflict(kinds map[string]bool) bool {
	for key := range kinds {
		for dir := path.Dir(key); dir != "."; dir = path.Dir(dir) {
			if isDir, ok := kinds[dir]; ok && !isDir {
				return true
			}
		}
	}
	return false
}

// ArchiveFormat_Pack encodes entries with a typed format selector.
func ArchiveFormat_Pack(ctx *Execution, format ArchiveFormat, entries *List[*ArchiveEntry], maxBytes Option[int]) Result[*Bytes, ArchiveError] {
	CheckCancelled(ctx)
	return Archive_Pack(ctx, entries, archiveFormatName(format), maxBytes)
}

// ArchiveFormat_Unpack decodes data with a typed format selector.
func ArchiveFormat_Unpack(ctx *Execution, format ArchiveFormat, data *Bytes, limits Option[*ArchiveLimits]) Result[*List[*ArchiveEntry], ArchiveError] {
	CheckCancelled(ctx)
	return Archive_Unpack(ctx, data, archiveFormatName(format), limits)
}

// Archive_Pack encodes entries as exactly "zip" or "tar", validating paths,
// duplicates and conflicts, with deterministic metadata.
func Archive_Pack(ctx *Execution, entries *List[*ArchiveEntry], format string, maxBytes Option[int]) Result[*Bytes, ArchiveError] {
	max := dfBudget(maxBytes)
	if max < 0 {
		return archiveFail[*Bytes]("InvalidInput")
	}
	seen := map[string]bool{}
	kinds := map[string]bool{}
	for _, f := range entries.Items {
		CheckCancelled(ctx)
		if !archivePathValid(f.Path, f.Directory) || f.Directory && len(dfBytes(f.Data)) != 0 {
			return archiveFail[*Bytes]("InvalidInput")
		}
		key := path.Clean(f.Path)
		if seen[key] {
			return archiveFail[*Bytes]("InvalidData")
		}
		seen[key] = true
		kinds[key] = f.Directory
	}
	if archiveConflict(kinds) {
		return archiveFail[*Bytes]("InvalidData")
	}
	if format == "zip" {
		for _, f := range entries.Items {
			name := f.Path
			if f.Directory {
				name = strings.TrimSuffix(name, "/") + "/"
			}
			if len(name) > 1<<16-1 { // ZIP stores the name length in 16 bits
				return archiveFail[*Bytes]("InvalidInput")
			}
		}
	}
	w := &dfLimitedWriter{max: max}
	switch format {
	case "tar":
		writer := tar.NewWriter(w)
		defer writer.Close()
		for _, f := range entries.Items {
			CheckCancelled(ctx)
			b := dfBytes(f.Data)
			header := &tar.Header{Name: f.Path, Mode: 0600, Size: int64(len(b)), ModTime: time.Unix(0, 0), Format: tar.FormatPAX}
			if f.Directory {
				header.Typeflag = tar.TypeDir
				header.Mode = 0700
				header.Name = strings.TrimSuffix(f.Path, "/") + "/"
			}
			if err := writer.WriteHeader(header); err != nil {
				return archiveFail[*Bytes]("LimitExceeded")
			}
			for len(b) > 0 {
				CheckCancelled(ctx)
				n := min(len(b), 65536)
				if _, err := writer.Write(b[:n]); err != nil {
					return archiveFail[*Bytes]("LimitExceeded")
				}
				b = b[n:]
			}
		}
		if err := writer.Close(); err != nil {
			return archiveFail[*Bytes]("LimitExceeded")
		}
	case "zip":
		writer := zip.NewWriter(w)
		defer writer.Close()
		for _, f := range entries.Items {
			CheckCancelled(ctx)
			header := &zip.FileHeader{Name: f.Path, Method: zip.Deflate}
			header.Modified = time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC)
			header.SetMode(0600)
			if f.Directory {
				header.Name = strings.TrimSuffix(header.Name, "/") + "/"
				header.Method = zip.Store
				header.SetMode(0700 | 1<<31)
			}
			entry, err := writer.CreateHeader(header)
			if err != nil {
				return archiveFail[*Bytes]("LimitExceeded")
			}
			b := dfBytes(f.Data)
			for len(b) > 0 {
				CheckCancelled(ctx)
				n := min(len(b), 65536)
				if _, err = entry.Write(b[:n]); err != nil {
					return archiveFail[*Bytes]("LimitExceeded")
				}
				b = b[n:]
			}
		}
		if err := writer.Close(); err != nil {
			return archiveFail[*Bytes]("LimitExceeded")
		}
	default:
		return archiveFail[*Bytes]("Unsupported")
	}
	return Ok[*Bytes, ArchiveError](NewBytes(append([]byte{}, w.Bytes()...)))
}

// Archive_Unpack decodes exactly "zip" or "tar" in memory, applying the entry
// count, per-entry and total byte limits.
func Archive_Unpack(ctx *Execution, data *Bytes, format string, limits Option[*ArchiveLimits]) Result[*List[*ArchiveEntry], ArchiveError] {
	count, entryMax, total := math.MaxInt, math.MaxInt, math.MaxInt
	if limits.Some {
		count, entryMax, total = dfBudget(limits.Val.MaxEntries), dfBudget(limits.Val.MaxEntryBytes), dfBudget(limits.Val.MaxTotalBytes)
	}
	if count < 0 || entryMax < 0 || total < 0 {
		return archiveFail[*List[*ArchiveEntry]]("InvalidInput")
	}
	out := []*ArchiveEntry{}
	seen := map[string]bool{}
	kinds := map[string]bool{}
	add := func(name string, directory bool, size int, reader io.Reader) string {
		CheckCancelled(ctx)
		if !archivePathValid(name, directory) {
			return "InvalidData"
		}
		key := path.Clean(name)
		if seen[key] {
			return "InvalidData"
		}
		seen[key] = true
		kinds[key] = directory
		if len(out) >= count || size > entryMax || size > total {
			return "LimitExceeded"
		}
		limit := min(entryMax, total)
		body, code := dfReadBounded(ctx, reader, limit)
		if code != "" {
			return code
		}
		if directory && len(body) != 0 {
			return "InvalidData"
		}
		total -= len(body)
		if directory {
			name = strings.TrimSuffix(name, "/") // canonical directory path has no trailing slash
		}
		out = append(out, &ArchiveEntry{Path: name, Directory: directory, Data: NewBytes(body)})
		return ""
	}
	input := dfBytes(data)
	switch format {
	case "tar":
		reader := tar.NewReader(bytes.NewReader(input))
		for {
			CheckCancelled(ctx)
			header, err := reader.Next()
			if err == io.EOF {
				break
			}
			if err != nil {
				return archiveFail[*List[*ArchiveEntry]]("InvalidData")
			}
			if header.Typeflag != tar.TypeReg && header.Typeflag != 0 /* legacy regular-file encoding */ && header.Typeflag != tar.TypeDir {
				return archiveFail[*List[*ArchiveEntry]]("Unsupported")
			}
			if code := add(header.Name, header.Typeflag == tar.TypeDir, FitInt(header.Size), reader); code != "" {
				return archiveFail[*List[*ArchiveEntry]](code)
			}
		}
	case "zip":
		reader, err := zip.NewReader(bytes.NewReader(input), int64(len(input)))
		if err != nil {
			return archiveFail[*List[*ArchiveEntry]]("InvalidData")
		}
		if len(reader.File) > count {
			return archiveFail[*List[*ArchiveEntry]]("LimitExceeded")
		}
		for _, file := range reader.File {
			CheckCancelled(ctx)
			if file.NonUTF8 && !utf8.ValidString(file.Name) || !file.Mode().IsRegular() && !file.Mode().IsDir() {
				return archiveFail[*List[*ArchiveEntry]]("Unsupported")
			}
			if file.UncompressedSize64 > uint64(entryMax) || file.UncompressedSize64 > uint64(total) {
				return archiveFail[*List[*ArchiveEntry]]("LimitExceeded")
			}
			entry, err := file.Open()
			if err != nil {
				return archiveFail[*List[*ArchiveEntry]]("InvalidData")
			}
			code := add(file.Name, file.FileInfo().IsDir(), int(file.UncompressedSize64), entry)
			closeErr := entry.Close()
			if code != "" {
				return archiveFail[*List[*ArchiveEntry]](code)
			}
			if closeErr != nil {
				return archiveFail[*List[*ArchiveEntry]]("InvalidData")
			}
		}
	default:
		return archiveFail[*List[*ArchiveEntry]]("Unsupported")
	}
	if archiveConflict(kinds) {
		return archiveFail[*List[*ArchiveEntry]]("InvalidData")
	}
	return Ok[*List[*ArchiveEntry], ArchiveError](NewList(out...))
}

// Errors_Message_ArchiveError returns Failed text verbatim, or a fixed archive
// diagnostic.
func Errors_Message_ArchiveError(_ *Execution, e ArchiveError) string {
	switch e := e.(type) {
	case ArchiveError_Failed:
		return e.Message
	case ArchiveError_InvalidInput:
		return dfMessage("archive", reasonInvalidInput)
	case ArchiveError_InvalidData:
		return dfMessage("archive", reasonInvalidData)
	case ArchiveError_LimitExceeded:
		return dfMessage("archive", reasonLimitExceeded)
	case ArchiveError_Unsupported:
		return dfMessage("archive", reasonUnsupported)
	}
	return dfMessage("archive", "operation failed")
}
