package msruntime

import (
	"strconv"
	"sync"
	"time"
)

const defaultAsyncLogQueue = 8192

// asyncLogItem is a queued record, or a flush marker when done is set.
type asyncLogItem struct {
	data *Bytes
	done chan Result[Unit, LogError]
}

// asyncFileTransport queues records on a BlockingQueue; one writer goroutine
// appends them to the file and rotates it.
type asyncFileTransport struct {
	files     FileSystem
	path      string
	maxBytes  int // zero means no limit
	maxAge    time.Duration
	maxFiles  int // zero means unlimited
	capacity  int
	queue     *BlockingQueue[asyncLogItem]
	writerCtx *Execution
	finished  chan struct{}

	mu      sync.Mutex // guards closed, pending, and the check-then-put in Write
	closed  bool
	pending LogError

	// Writer-goroutine state.
	handle FileHandle
	size   int
	opened time.Time
}

var _ Transport = (*asyncFileTransport)(nil)

// Log_AsyncFileTransport appends records to a file from a background writer.
func Log_AsyncFileTransport(ctx *Execution, path string, maxBytes Option[int], maxAge Option[Duration], maxFiles Option[int], queueSize Option[int]) Result[Transport, LogError] {
	for _, limit := range []Option[int]{maxBytes, maxFiles, queueSize} {
		if limit.Some && limit.Val <= 0 {
			return logFail[Transport](LogError_InvalidInput{})
		}
	}
	if maxAge.Some && maxAge.Val <= 0 {
		return logFail[Transport](LogError_InvalidInput{})
	}
	t := &asyncFileTransport{files: hostRoots(ctx).Filesystem, path: path, capacity: defaultAsyncLogQueue, finished: make(chan struct{})}
	if maxBytes.Some {
		t.maxBytes = maxBytes.Val
	}
	if maxAge.Some {
		t.maxAge = time.Duration(maxAge.Val)
	}
	if maxFiles.Some {
		t.maxFiles = maxFiles.Val
	}
	if queueSize.Some {
		t.capacity = queueSize.Val
	}
	t.queue = NewBlockingQueue[asyncLogItem](Some(t.capacity))
	// The writer outlives the opening call; close ends it.
	t.writerCtx = Shield(ctx)
	if failure := t.openActive(); failure != nil {
		return logFail[Transport](failure)
	}
	go t.run()
	return Ok[Transport, LogError](t)
}

// openActive opens the active file and reads its size and start time.
func (t *asyncFileTransport) openActive() LogError {
	opened := t.files.Open(t.writerCtx, t.path, "a", 0600)
	if opened.Failed {
		return LogError_FileSystem{Cause: opened.Err}
	}
	t.handle = opened.Val
	t.size, t.opened = 0, time.Now()
	if info := t.handle.Stat(t.writerCtx); !info.Failed {
		t.size = info.Val.Size
		if t.size > 0 {
			t.opened = time.Unix(info.Val.Modified.Seconds, int64(info.Val.Modified.Nanos))
		}
	}
	return nil
}

func (t *asyncFileTransport) run() {
	defer close(t.finished)
	for {
		item := BlockingQueue_Take(t.writerCtx, t.queue)
		if !item.Some {
			break
		}
		var result Result[Unit, LogError]
		if item.Val.done != nil {
			result = t.sync()
			item.Val.done <- result
			continue
		}
		result = t.append(item.Val.data)
		if result.Failed {
			t.setPending(result.Err)
		}
	}
	if t.handle != nil {
		t.handle.Close(t.writerCtx)
	}
}

func (t *asyncFileTransport) setPending(failure LogError) {
	t.mu.Lock()
	if t.pending == nil {
		t.pending = failure
	}
	t.mu.Unlock()
}

func (t *asyncFileTransport) takePending() LogError {
	t.mu.Lock()
	defer t.mu.Unlock()
	failure := t.pending
	t.pending = nil
	return failure
}

func (t *asyncFileTransport) sync() Result[Unit, LogError] {
	if t.handle == nil {
		return logFail[Unit](LogError_Closed{})
	}
	if synced := t.handle.Sync(t.writerCtx); synced.Failed {
		return logFail[Unit](LogError_FileSystem{Cause: synced.Err})
	}
	return Ok[Unit, LogError](Unit{})
}

func (t *asyncFileTransport) append(data *Bytes) Result[Unit, LogError] {
	if t.handle == nil {
		// An earlier rotation could not reopen the file; retry.
		if failure := t.openActive(); failure != nil {
			return logFail[Unit](failure)
		}
	}
	n := len(data.Data)
	due := t.size > 0 && (t.maxBytes > 0 && t.size+n > t.maxBytes || t.maxAge > 0 && time.Since(t.opened) >= t.maxAge)
	if due {
		if failure := t.rotate(); failure != nil {
			return logFail[Unit](failure)
		}
	}
	if written := t.handle.Write(t.writerCtx, data); written.Failed {
		return logFail[Unit](LogError_FileSystem{Cause: written.Err})
	}
	t.size += n
	return Ok[Unit, LogError](Unit{})
}

func (t *asyncFileTransport) numbered(i int) string {
	if i == 0 {
		return t.path
	}
	return t.path + "." + strconv.Itoa(i)
}

func (t *asyncFileTransport) exists(path string) bool {
	return !t.files.Stat(t.writerCtx, path, false).Failed
}

// rotate shifts path to path.1, path.1 to path.2, and so on, deletes files
// beyond max_files, and opens a fresh active file.
func (t *asyncFileTransport) rotate() LogError {
	t.handle.Close(t.writerCtx)
	t.handle = nil
	last := 0
	for t.exists(t.numbered(last + 1)) {
		last++
	}
	// Keep the active file plus maxFiles-1 rotated ones after the shift.
	keep := last + 1
	if t.maxFiles > 0 {
		keep = t.maxFiles - 1
	}
	for i := last; i >= keep && i > 0; i-- {
		if removed := t.files.Remove(t.writerCtx, t.numbered(i), false); removed.Failed {
			return LogError_FileSystem{Cause: removed.Err}
		}
	}
	for i := min(last, keep-1); i >= 0; i-- {
		if renamed := t.files.Rename(t.writerCtx, t.numbered(i), t.numbered(i+1)); renamed.Failed {
			return LogError_FileSystem{Cause: renamed.Err}
		}
	}
	if keep == 0 {
		if removed := t.files.Remove(t.writerCtx, t.path, false); removed.Failed {
			return LogError_FileSystem{Cause: removed.Err}
		}
	}
	return t.openActive()
}

func (t *asyncFileTransport) Write(_ *Execution, data *Bytes) Result[Unit, LogError] {
	if failure := t.takePending(); failure != nil {
		return logFail[Unit](failure)
	}
	// The lock makes the length check and put atomic among producers, so put
	// never waits: only the writer removes items.
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.closed {
		return logFail[Unit](LogError_Closed{})
	}
	if BlockingQueue_Length(nil, t.queue) >= t.capacity {
		return logFail[Unit](LogError_LimitExceeded{})
	}
	copied := append([]byte(nil), data.Data...)
	BlockingQueue_Put(t.writerCtx, t.queue, asyncLogItem{data: &Bytes{Data: copied}})
	return Ok[Unit, LogError](Unit{})
}

func (t *asyncFileTransport) Flush(ctx *Execution) Result[Unit, LogError] {
	t.mu.Lock()
	closed := t.closed
	t.mu.Unlock()
	if closed {
		return logFail[Unit](LogError_Closed{})
	}
	done := make(chan Result[Unit, LogError], 1)
	if !BlockingQueue_Put(ctx, t.queue, asyncLogItem{done: done}) {
		return logFail[Unit](LogError_Closed{})
	}
	select {
	case result := <-done:
		if result.Failed {
			return result
		}
	case <-ctx.Context.Done():
		CheckCancelled(ctx)
	}
	if failure := t.takePending(); failure != nil {
		return logFail[Unit](failure)
	}
	return Ok[Unit, LogError](Unit{})
}

func (t *asyncFileTransport) Close(*Execution) Unit {
	t.mu.Lock()
	t.closed = true
	t.mu.Unlock()
	BlockingQueue_Close(nil, t.queue)
	<-t.finished
	return Unit{}
}
