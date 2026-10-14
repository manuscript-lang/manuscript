package msruntime

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/hostos"
)

func init() {
	LibraryMethods = append(LibraryMethods, LibraryMethod{"FileSystem", "copy", libraryResult("Unit", "FileSystemError"), []LibraryParam{{"source", "String"}, {"destination", "String"}, {"options", "CopyOptions"}, {"filter", "Optional[fn(source:String;destination:String)->Bool]"}}})
}

type libraryCopyOptions struct {
	recursive, replace, errorOnExists, dereference, preserve, verbatim bool
	clone                                                              string
	entries, bytes                                                     int64
	filter                                                             Value
	ancestors                                                          map[string]bool
}

var errLibraryInput = errors.New("invalid filesystem operation")

func (f *libraryFileSystem) copy(ctx *Execution, r string, a []Value) Value {
	source, ok := f.path(a[0].(string))
	dest, ok2 := f.path(a[1].(string))
	fields := a[2].(Record).Fields
	options := &libraryCopyOptions{recursive: fields["recursive"].(bool), replace: fields["replace"].(bool), errorOnExists: fields["error_on_exists"].(bool), dereference: fields["dereference"].(bool), preserve: fields["preserve_timestamps"].(bool), verbatim: fields["verbatim_symlinks"].(bool), clone: fields["clone"].(string), entries: fields["max_entries"].(int64), bytes: fields["max_bytes"].(int64), ancestors: map[string]bool{}}
	filter := a[3].(Alternative)
	if filter.Tag == "some" {
		options.filter = filter.Fields[0]
	}
	if !ok || !ok2 || options.entries < 0 || options.bytes < 0 || options.clone != "none" && options.clone != "try" && options.clone != "force" {
		return libraryError(r, "InvalidInput", "")
	}
	if err := libraryCopyCheckDestination(source, dest, options.dereference); err != nil {
		return libraryCopyError(r, err)
	}
	return libraryCopyError(r, options.copy(ctx, source, dest))
}
func libraryCopyError(r string, err error) Value {
	if errors.Is(err, errLibraryInput) {
		return libraryError(r, "InvalidInput", "")
	}
	if errors.Is(err, errLibraryLimit) {
		return libraryError(r, "LimitExceeded", "")
	}
	return libraryOSResult(r, Unit{}, err)
}
func libraryCopyCheckDestination(source, dest string, follow bool) error {
	canonical, err := filepath.EvalSymlinks(source)
	if !follow {
		if info, statErr := os.Lstat(source); statErr == nil && info.Mode()&os.ModeSymlink != 0 {
			var parent string
			parent, err = filepath.EvalSymlinks(filepath.Dir(source))
			canonical = filepath.Join(parent, filepath.Base(source))
		}
	}
	if err != nil {
		return err
	}
	ancestor := dest
	var suffix []string
	for {
		_, err = os.Lstat(ancestor)
		if err == nil {
			break
		}
		if !errors.Is(err, os.ErrNotExist) {
			return err
		}
		parent := filepath.Dir(ancestor)
		if parent == ancestor {
			return errLibraryInput
		}
		suffix = append(suffix, filepath.Base(ancestor))
		ancestor = parent
	}
	canonicalDest, err := filepath.EvalSymlinks(ancestor)
	if err != nil {
		return err
	}
	for i := len(suffix) - 1; i >= 0; i-- {
		canonicalDest = filepath.Join(canonicalDest, suffix[i])
	}
	rel, err := filepath.Rel(canonical, canonicalDest)
	if err == nil && (rel == "." || rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator))) {
		return errLibraryInput
	}
	return nil
}
func (o *libraryCopyOptions) copy(ctx *Execution, source, dest string) error {
	CheckCancelled(ctx)
	if o.entries <= 0 {
		return errLibraryLimit
	}
	o.entries--
	if o.filter != nil && !Invoke(ctx, o.filter, []Argument{{"source", source}, {"destination", dest}}).(bool) {
		return nil
	}
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if o.dereference {
		info, err = os.Stat(source)
		if err != nil {
			return err
		}
	}
	previous, err := os.Lstat(dest)
	exists := err == nil
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if exists && os.SameFile(info, previous) {
		return errLibraryInput
	}
	if info.IsDir() {
		if !o.recursive {
			return errLibraryInput
		}
		if exists && !previous.IsDir() {
			return errLibraryInput
		}
		canonical, err := filepath.EvalSymlinks(source)
		if err != nil {
			return err
		}
		if o.ancestors[canonical] {
			return errLibraryInput
		}
		o.ancestors[canonical] = true
		defer delete(o.ancestors, canonical)
		if !exists {
			if err = os.Mkdir(dest, 0700); err != nil {
				return err
			}
		}
		directory, err := os.Open(source)
		if err != nil {
			return err
		}
		defer directory.Close()
		for {
			batch, err := directory.ReadDir(64)
			for _, entry := range batch {
				if err := o.copy(ctx, filepath.Join(source, entry.Name()), filepath.Join(dest, entry.Name())); err != nil {
					return err
				}
			}
			if err == io.EOF {
				break
			}
			if err != nil {
				return err
			}
		}
		if !exists {
			if err = os.Chmod(dest, info.Mode()); err != nil {
				return err
			}
		}
		if o.preserve {
			return os.Chtimes(dest, libraryStatTime(hostos.StatInfo(info).Atime, info).t, info.ModTime())
		}
		return nil
	}
	if exists && !o.replace {
		if o.errorOnExists {
			return os.ErrExist
		}
		return nil
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(source)
		if err != nil {
			return err
		}
		if !o.verbatim && !filepath.IsAbs(target) {
			target = filepath.Join(filepath.Dir(source), target)
		}
		if exists {
			if err = os.Remove(dest); err != nil {
				return err
			}
		}
		return os.Symlink(target, dest)
	}
	if !info.Mode().IsRegular() {
		return errLibraryInput
	}
	if info.Size() > o.bytes {
		return errLibraryLimit
	}
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	acquired, err := input.Stat()
	if err != nil {
		return err
	}
	if !os.SameFile(info, acquired) {
		return errLibraryInput
	}
	if exists {
		if err = os.Remove(dest); err != nil {
			return err
		}
	}
	if o.clone != "none" {
		err = hostos.CloneFile(source, dest)
		CheckCancelled(ctx)
		if err == nil {
			cloned, err := os.Stat(dest)
			if err != nil {
				return err
			}
			if cloned.Size() > o.bytes {
				return errLibraryLimit
			}
			o.bytes -= cloned.Size()
			if err = os.Chmod(dest, info.Mode()); err != nil {
				return err
			}
			if o.preserve {
				return os.Chtimes(dest, libraryStatTime(hostos.StatInfo(info).Atime, info).t, info.ModTime())
			}
			return nil
		}
		// A failed clone may have created an empty destination; clean up only the
		// file the adapter created, before taking the ordinary copy fallback.
		if o.clone == "force" {
			return err
		}
		if _, statErr := os.Lstat(dest); statErr == nil {
			return err
		}
	}
	output, err := os.OpenFile(dest, os.O_WRONLY|os.O_CREATE|os.O_EXCL, info.Mode())
	if err != nil {
		return err
	}
	defer output.Close()
	buffer := make([]byte, 65536)
	for {
		CheckCancelled(ctx)
		n, err := input.Read(buffer)
		if int64(n) > o.bytes {
			return errLibraryLimit
		}
		if n > 0 {
			if _, err := libraryWriteChunks(ctx, output, buffer[:n], nil); err != nil {
				return err
			}
			o.bytes -= int64(n)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	if err = output.Chmod(info.Mode()); err != nil {
		return err
	}
	if err = output.Close(); err != nil {
		return err
	}
	if o.preserve {
		return os.Chtimes(dest, libraryStatTime(hostos.StatInfo(info).Atime, info).t, info.ModTime())
	}
	return nil
}
