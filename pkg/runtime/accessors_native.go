package msruntime

func (q *Queue) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "length":
		return QueueLengthRead(ctx, q)
	case "is_empty":
		return QueueIsEmptyRead(ctx, q)
	case "peek":
		return QueuePeekRead(ctx, q)
	}
	return Panic("unknown Queue accessor")
}
func (q *PriorityQueue) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "length":
		return PriorityQueueLengthRead(ctx, q)
	case "is_empty":
		return PriorityQueueIsEmptyRead(ctx, q)
	case "peek":
		return PriorityQueuePeekRead(ctx, q)
	}
	return Panic("unknown PriorityQueue accessor")
}
func (g *SynchronizedGuard) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "value":
		return SynchronizedGuardValueRead(ctx, g)
	}
	return Panic("unknown SynchronizedGuard accessor")
}
func (d *libraryDirectory) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "path":
		return DirectoryPathRead(ctx, d)
	}
	return Panic("unknown Directory accessor")
}
func (t *libraryTemporary) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "path":
		return TemporaryDirectoryPathRead(ctx, t)
	}
	return Panic("unknown TemporaryDirectory accessor")
}
func (l *libraryLogger) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "level":
		return LoggerLevelRead(ctx, l)
	}
	return Panic("unknown Logger accessor")
}
func (p libraryPaths) ReadAccessor(ctx *Execution, name string) Value {
	switch name {
	case "separator":
		return PathOperationsSeparatorRead(ctx, p)
	case "delimiter":
		return PathOperationsDelimiterRead(ctx, p)
	}
	return Panic("unknown PathOperations accessor")
}

func (*Queue) accessorKind() string { return "Queue" }

func (*PriorityQueue) accessorKind() string { return "PriorityQueue" }

func (*SynchronizedGuard) accessorKind() string { return "SynchronizedGuard" }

func (*libraryDirectory) accessorKind() string { return "Directory" }

func (*libraryTemporary) accessorKind() string { return "TemporaryDirectory" }

func (*libraryLogger) accessorKind() string { return "Logger" }

func (libraryPaths) accessorKind() string { return "PathOperations" }
