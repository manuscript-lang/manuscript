package msruntime

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"unicode/utf8"

	"github.com/fsnotify/fsnotify"
)

func init() {
	LibraryMethods = append(LibraryMethods, LibraryMethod{"FileSystem", "watch_native", libraryResult("FileWatcher", "FileSystemError"), []LibraryParam{{"path", "String"}, {"recursive", "Bool"}, {"max_entries", "Int"}, {"max_events", "Int"}, {"overflow", "String"}}})
}

// Native watches consume kernel events independently of next() so recursive
// directory admission and transient-event retention do not depend on readers.
type libraryNativeWatcher struct {
	native           *fsnotify.Watcher
	recursive        bool
	max              int64
	overflow         string
	watched          map[string]bool
	mu               sync.Mutex
	closed           bool
	terminal         error
	done, workerDone chan struct{}
	events           chan fsnotify.Event
	gate             chan struct{}
}

func libraryNewNativeWatch(ctx *Execution, r, path string, recursive bool, max, events int64, overflow string) Value {
	if max <= 0 || events <= 0 || events > 1048576 || overflow != "error" && overflow != "ignore" {
		return libraryError(r, "InvalidInput", "")
	}
	native, err := fsnotify.NewWatcher()
	if err != nil {
		return libraryOSResult(r, nil, err)
	}
	delivered := false
	defer func() {
		if !delivered {
			native.Close()
		}
	}()
	w := &libraryNativeWatcher{native: native, recursive: recursive, max: max, overflow: overflow, watched: map[string]bool{}, done: make(chan struct{}), workerDone: make(chan struct{}), events: make(chan fsnotify.Event, int(events)), gate: make(chan struct{}, 1)}
	if err = w.addTree(path); err != nil {
		if errors.Is(err, errLibraryLimit) {
			return libraryError(r, "LimitExceeded", "")
		}
		if errors.Is(err, errLibraryEncoding) {
			return libraryError(r, "Unsupported", "")
		}
		return libraryOSResult(r, nil, err)
	}
	CheckCancelled(ctx)
	go w.pump()
	delivered = true
	return libraryOK(r, ViewOf("@std/FileWatcher", w))
}
func (w *libraryNativeWatcher) addTree(root string) error {
	return filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		select {
		case <-w.done:
			return os.ErrClosed
		default:
		}
		if err != nil {
			return err
		}
		if !utf8.ValidString(path) {
			return errLibraryEncoding
		}
		if path != root && !entry.IsDir() {
			return nil
		}
		if !w.watched[path] {
			if int64(len(w.watched)) >= w.max {
				return errLibraryLimit
			}
			if err = w.native.Add(path); err != nil {
				return err
			}
			w.watched[path] = true
		}
		if !w.recursive && entry.IsDir() {
			return filepath.SkipDir
		}
		return nil
	})
}
func (w *libraryNativeWatcher) fail(err error) { w.mu.Lock(); w.terminal = err; w.mu.Unlock() }
func (w *libraryNativeWatcher) pump() {
	defer close(w.workerDone)
	defer close(w.events)
	defer w.native.Close()
	for {
		select {
		case <-w.done:
			return
		case err, ok := <-w.native.Errors:
			if !ok {
				return
			}
			if errors.Is(err, fsnotify.ErrEventOverflow) {
				if w.overflow == "ignore" {
					continue
				}
				err = errLibraryLimit
			}
			w.fail(err)
			return
		case event, ok := <-w.native.Events:
			if !ok {
				return
			}
			if event.Op&(fsnotify.Remove|fsnotify.Rename) != 0 {
				for watched := range w.watched {
					if watched == event.Name || strings.HasPrefix(watched, event.Name+string(os.PathSeparator)) {
						delete(w.watched, watched)
					}
				}
			}
			if w.recursive && event.Has(fsnotify.Create) {
				if info, err := os.Lstat(event.Name); err == nil && info.IsDir() {
					if err = w.addTree(event.Name); err != nil && !errors.Is(err, os.ErrNotExist) {
						w.fail(err)
						return
					}
				}
			}
			if !utf8.ValidString(event.Name) {
				w.fail(errLibraryEncoding)
				return
			}
			select {
			case <-w.done:
				return
			case w.events <- event:
			default:
				if w.overflow == "error" {
					w.fail(errLibraryLimit)
					return
				}
			}
		}
	}
}
func (w *libraryNativeWatcher) failure(r string) Value {
	w.mu.Lock()
	err, closed := w.terminal, w.closed
	w.mu.Unlock()
	if closed {
		return libraryError(r, "Closed", "")
	}
	if err == nil {
		return nil
	}
	if errors.Is(err, errLibraryLimit) {
		return libraryError(r, "LimitExceeded", "")
	}
	if errors.Is(err, errLibraryEncoding) {
		return libraryError(r, "Unsupported", "")
	}
	return libraryOSResult(r, nil, err)
}
func (w *libraryNativeWatcher) Operation(name string) Function {
	return libraryMethod("FileWatcher", name, func(ctx *Execution, r string, _ []Value) Value {
		if name == "close" {
			w.mu.Lock()
			if !w.closed {
				w.closed = true
				close(w.done)
			}
			w.mu.Unlock()
			w.native.Close()
			<-w.workerDone
			w.gate <- struct{}{}
			<-w.gate
			return Unit{}
		}
		select {
		case w.gate <- struct{}{}:
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		case <-w.done:
			return libraryError(r, "Closed", "")
		}
		defer func() { <-w.gate }()
		if failure := w.failure(r); failure != nil {
			return failure
		}
		select {
		case <-ctx.Context.Done():
			CheckCancelled(ctx)
		case <-w.done:
			return libraryError(r, "Closed", "")
		case event, ok := <-w.events:
			if failure := w.failure(r); failure != nil {
				return failure
			}
			if !ok {
				return libraryError(r, "Closed", "")
			}
			CheckCancelled(ctx)
			kind := "change"
			if event.Op&(fsnotify.Create|fsnotify.Remove|fsnotify.Rename) != 0 {
				kind = "rename"
			}
			return libraryOK(r, libraryList("@std/FileEvent", []Value{Record{"@std/FileEvent", map[string]Value{"path": event.Name, "kind": kind}}}))
		}
		return Panic("unreachable watch wait")
	})
}
