package msruntime

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/manuscript-lang/manuscript/internal/hostos"
)

// copyError maps the outcome of a copy or glob traversal to its Result.
func copyError(err error) Result[Unit, FileSystemError] {
	switch {
	case errors.Is(err, errInvalidInput):
		return fsInvalid[Unit]()
	case errors.Is(err, errLimit):
		return fsFail[Unit](FileSystemError_LimitExceeded{})
	}
	return fsUnit(err)
}

// withinPath reports whether target is source or lies inside it.
func withinPath(source, target string) bool {
	rel, err := filepath.Rel(source, target)
	return err == nil && (rel == "." || rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator)))
}

// resolveDestination resolves the existing ancestors of dest through symlinks,
// so a copy into the source through a link is detected.
func resolveDestination(dest string) (string, error) {
	ancestor := dest
	var suffix []string
	for {
		_, err := os.Lstat(ancestor)
		if err == nil {
			break
		}
		if !errors.Is(err, os.ErrNotExist) {
			return "", err
		}
		parent := filepath.Dir(ancestor)
		if parent == ancestor {
			return "", errInvalidInput
		}
		suffix = append(suffix, filepath.Base(ancestor))
		ancestor = parent
	}
	real, err := filepath.EvalSymlinks(ancestor)
	if err != nil {
		return "", err
	}
	for i := len(suffix) - 1; i >= 0; i-- {
		real = filepath.Join(real, suffix[i])
	}
	return real, nil
}

type copier struct {
	ctx                                                                *Execution
	recursive, replace, errorOnExists, dereference, preserve, verbatim bool
	clone                                                              string
	entries, bytes                                                     int
	filter                                                             func(*Execution, string, string) bool
	ancestors                                                          map[string]bool
}

func (f *osFileSystem) Copy(ctx *Execution, source, destination string, options *CopyOptions, filter Option[func(ctx *Execution, a0 string, a1 string) bool]) Result[Unit, FileSystemError] {
	entries, ok1 := optionLimit(options.MaxEntries, unlimited)
	bytes, ok2 := optionLimit(options.MaxBytes, unlimited)
	src, ok := f.path(source)
	dest, ok3 := f.path(destination)
	c := &copier{ctx: ctx, recursive: options.Recursive, replace: options.Replace, errorOnExists: options.ErrorOnExists, dereference: options.Dereference, preserve: options.PreserveTimestamps, verbatim: options.VerbatimSymlinks, clone: options.Clone, entries: entries, bytes: bytes, ancestors: map[string]bool{}}
	if filter.Some {
		c.filter = filter.Val
	}
	if !ok || !ok1 || !ok2 || !ok3 || c.clone != "none" && c.clone != "try" && c.clone != "force" {
		return fsInvalid[Unit]()
	}
	if err := copyCheckDestination(src, dest, c.dereference); err != nil {
		return copyError(err)
	}
	return copyError(c.copy(src, dest))
}

func copyCheckDestination(source, dest string, follow bool) error {
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
	canonicalDest, err := resolveDestination(dest)
	if err != nil {
		return err
	}
	if withinPath(canonical, canonicalDest) {
		return errInvalidInput
	}
	return nil
}

func (c *copier) copy(source, dest string) error {
	CheckCancelled(c.ctx)
	if c.entries <= 0 {
		return errLimit
	}
	c.entries--
	if c.filter != nil && !c.filter(c.ctx, source, dest) {
		return nil
	}
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if c.dereference {
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
		return errInvalidInput
	}
	if info.IsDir() {
		return c.copyDirectory(source, dest, info, previous, exists)
	}
	if exists && !c.replace {
		if c.errorOnExists {
			return os.ErrExist
		}
		return nil
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(source)
		if err != nil {
			return err
		}
		if !c.verbatim && !filepath.IsAbs(target) {
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
		return errInvalidInput
	}
	if info.Size() > int64(c.bytes) {
		return errLimit
	}
	return c.copyFile(source, dest, info, exists)
}

func (c *copier) copyDirectory(source, dest string, info, previous os.FileInfo, exists bool) error {
	if !c.recursive {
		return errInvalidInput
	}
	if exists && !previous.IsDir() {
		return errInvalidInput
	}
	canonical, err := filepath.EvalSymlinks(source)
	if err != nil {
		return err
	}
	if c.ancestors[canonical] {
		return errInvalidInput
	}
	c.ancestors[canonical] = true
	defer delete(c.ancestors, canonical)
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
			if err := c.copy(filepath.Join(source, entry.Name()), filepath.Join(dest, entry.Name())); err != nil {
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
	if c.preserve {
		return os.Chtimes(dest, statTime(hostos.StatInfo(info).Atime, info), info.ModTime())
	}
	return nil
}

func (c *copier) copyFile(source, dest string, info os.FileInfo, exists bool) error {
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
		return errInvalidInput
	}
	if exists {
		if err = os.Remove(dest); err != nil {
			return err
		}
	}
	if c.clone != "none" {
		err = hostos.CloneFile(source, dest)
		CheckCancelled(c.ctx)
		if err == nil {
			cloned, err := os.Stat(dest)
			if err != nil {
				return err
			}
			if cloned.Size() > int64(c.bytes) {
				return errLimit
			}
			c.bytes -= int(cloned.Size())
			if err = os.Chmod(dest, info.Mode()); err != nil {
				return err
			}
			if c.preserve {
				return os.Chtimes(dest, statTime(hostos.StatInfo(info).Atime, info), info.ModTime())
			}
			return nil
		}
		// A failed clone may have created an empty destination; clean up only
		// the file the adapter created, before taking the ordinary copy fallback.
		if c.clone == "force" {
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
		CheckCancelled(c.ctx)
		n, err := input.Read(buffer)
		if int(n) > c.bytes {
			return errLimit
		}
		if n > 0 {
			if _, err := writeChunks(c.ctx, output, buffer[:n], nil); err != nil {
				return err
			}
			c.bytes -= int(n)
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
	if c.preserve {
		return os.Chtimes(dest, statTime(hostos.StatInfo(info).Atime, info), info.ModTime())
	}
	return nil
}

func (f *osFileSystem) CopyTree(ctx *Execution, source, destination string, replace bool, maxEntries, maxBytes Option[int]) Result[Unit, FileSystemError] {
	entries, ok1 := optionLimit(maxEntries, unlimited)
	bytes, ok2 := optionLimit(maxBytes, unlimited)
	p, ok := f.path(source)
	dest, ok3 := f.path(destination)
	if !ok || !ok1 || !ok2 || !ok3 {
		return fsInvalid[Unit]()
	}
	real, err := filepath.EvalSymlinks(p)
	if err != nil {
		return fsUnit(err)
	}
	// Resolve existing destination ancestors to prevent copying into the source
	// through a symlink. Walking never follows source symlinks.
	resolved, err := resolveDestination(dest)
	if err != nil {
		return copyError(err)
	}
	if withinPath(real, resolved) {
		return fsInvalid[Unit]()
	}
	return copyError(copyTree(ctx, p, dest, replace, &entries, &bytes))
}

func copyTree(ctx *Execution, source, dest string, replace bool, entries, bytes *int) error {
	CheckCancelled(ctx)
	if *entries == 0 {
		return errLimit
	}
	*entries--
	info, err := os.Lstat(source)
	if err != nil {
		return err
	}
	if old, err := os.Lstat(dest); err == nil {
		if os.SameFile(info, old) {
			return errors.New("source and destination are the same file")
		}
		if !replace {
			return os.ErrExist
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(source)
		if err != nil {
			return err
		}
		if replace {
			if err = os.Remove(dest); err != nil && !errors.Is(err, os.ErrNotExist) {
				return err
			}
		}
		return os.Symlink(target, dest)
	}
	if info.IsDir() {
		if old, err := os.Lstat(dest); err == nil && !old.IsDir() {
			return errors.New("destination is not a directory")
		}
		if err = os.Mkdir(dest, info.Mode().Perm()); err != nil && !errors.Is(err, os.ErrExist) {
			return err
		}
		dir, err := os.Open(source)
		if err != nil {
			return err
		}
		defer dir.Close()
		for {
			batch, err := dir.ReadDir(64)
			for _, entry := range batch {
				if err := copyTree(ctx, filepath.Join(source, entry.Name()), filepath.Join(dest, entry.Name()), replace, entries, bytes); err != nil {
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
		return nil
	}
	if !info.Mode().IsRegular() {
		return errors.New("copy_tree requires regular files, directories, or symlinks")
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	if replace {
		if err := os.Remove(dest); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	out, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_EXCL, info.Mode().Perm())
	if err != nil {
		return err
	}
	defer out.Close()
	buffer := make([]byte, 65536)
	for {
		CheckCancelled(ctx)
		n, err := in.Read(buffer)
		if int(n) > *bytes {
			return errLimit
		}
		if n > 0 {
			if _, e := writeChunks(ctx, out, buffer[:n], nil); e != nil {
				return e
			}
			*bytes -= int(n)
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
	}
	return out.Close()
}

func (f *osFileSystem) GlobEntries(ctx *Execution, path string, options *GlobOptions, exclude Option[func(ctx *Execution, a0 *PathEntry) bool]) Result[*List[*PathEntry], FileSystemError] {
	fail := func(e FileSystemError) Result[*List[*PathEntry], FileSystemError] {
		return fsFail[*List[*PathEntry]](e)
	}
	root, ok := f.path(path)
	remaining, ok1 := optionLimit(options.MaxEntries, unlimited)
	maxResults, ok2 := optionLimit(options.MaxResults, unlimited)
	if !ok || !ok1 || !ok2 {
		return fail(FileSystemError_InvalidInput{})
	}
	patterns, excluded := options.Patterns.Items, options.Exclude.Items
	for _, pattern := range append(append([]string{}, patterns...), excluded...) {
		if !fsValidGlob(filepath.ToSlash(pattern)) {
			return fail(FileSystemError_InvalidInput{})
		}
	}
	follow := options.FollowLinks
	items := map[string]*PathEntry{}
	ancestors := map[string]bool{}
	var visit func(string) error
	visit = func(path string) error {
		CheckCancelled(ctx)
		if remaining == 0 {
			return errLimit
		}
		remaining--
		info, err := os.Lstat(path)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if !utf8.ValidString(rel) || !utf8.ValidString(info.Name()) {
			return errEncoding
		}
		value := &PathEntry{Path: filepath.ToSlash(rel), Entry: directoryEntryOf(info.Name(), info.IsDir(), info.Mode()&os.ModeSymlink != 0)}
		candidate := filepath.ToSlash(rel)
		absolute := filepath.ToSlash(path)
		for _, pattern := range excluded {
			target := candidate
			if filepath.IsAbs(pattern) {
				target = absolute
			}
			if fsGlobMatch(target, filepath.ToSlash(pattern)) {
				return nil
			}
		}
		if exclude.Some && exclude.Val(ctx, value) {
			return nil
		}
		for _, pattern := range patterns {
			target := candidate
			if filepath.IsAbs(pattern) {
				target = absolute
			}
			if fsGlobMatch(target, filepath.ToSlash(pattern)) {
				if _, exists := items[value.Path]; !exists {
					if len(items) >= maxResults {
						return errLimit
					}
					items[value.Path] = value
				}
				break
			}
		}
		if info.Mode()&os.ModeSymlink != 0 && follow {
			info, err = os.Stat(path)
			if errors.Is(err, os.ErrNotExist) {
				return nil
			}
			if err != nil {
				return err
			}
		}
		if !info.IsDir() {
			return nil
		}
		canonical, err := filepath.EvalSymlinks(path)
		if err != nil {
			return err
		}
		if ancestors[canonical] {
			return nil
		}
		ancestors[canonical] = true
		defer delete(ancestors, canonical)
		directory, err := os.Open(path)
		if err != nil {
			return err
		}
		defer directory.Close()
		for {
			batch, err := directory.ReadDir(64)
			for _, entry := range batch {
				if err := visit(filepath.Join(path, entry.Name())); err != nil {
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
		return nil
	}
	// Relative parent and absolute patterns can start outside cwd, as in Node.
	// The caller's filesystem capability already supplies that OS authority.
	roots := map[string]bool{root: true}
	for _, pattern := range patterns {
		pattern = filepath.FromSlash(pattern)
		base := root
		if filepath.IsAbs(pattern) {
			base = filepath.VolumeName(pattern) + string(os.PathSeparator)
			pattern = strings.TrimLeft(strings.TrimPrefix(pattern, filepath.VolumeName(pattern)), "/\\")
		}
		for _, part := range strings.Split(pattern, string(os.PathSeparator)) {
			if part == ".." {
				base = filepath.Dir(base)
			} else if part == "." || part == "" {
				continue
			} else if strings.ContainsAny(part, "*?[]{}()!") {
				break
			} else {
				base = filepath.Join(base, part)
			}
		}
		if info, err := os.Lstat(base); err == nil && info.IsDir() {
			roots[base] = true
		} else if base != root {
			roots[filepath.Dir(base)] = true
		}
	}
	starts := make([]string, 0, len(roots))
	for start := range roots {
		starts = append(starts, start)
	}
	sort.Slice(starts, func(i, j int) bool {
		if len(starts[i]) == len(starts[j]) {
			return starts[i] < starts[j]
		}
		return len(starts[i]) < len(starts[j])
	})
	var selected []string
	for _, start := range starts {
		covered := false
		for _, parent := range selected {
			if withinPath(parent, start) {
				covered = true
				break
			}
		}
		if !covered {
			selected = append(selected, start)
		}
	}
	for _, start := range selected {
		if err := visit(start); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if errors.Is(err, errEncoding) {
				return fail(FileSystemError_Unsupported{})
			}
			result := copyError(err)
			return fail(result.Err)
		}
	}
	keys := make([]string, 0, len(items))
	for key := range items {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	values := make([]*PathEntry, 0, len(keys))
	for _, key := range keys {
		values = append(values, items[key])
	}
	return fsOK(NewList(values...))
}
