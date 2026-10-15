// Code generated from the standard error cases of std_types_gen.go; see TestErrorMessageCoverage. DO NOT EDIT.
//
// Diagnostics stay independent of input values: URLs, data, and host arguments can
// contain secrets. Explicit Failed and Crashed messages are returned verbatim.

package rt

// Errors_Message_ArchiveError is the Error message of ArchiveError.
func Errors_Message_ArchiveError(ctx *Execution, cause ArchiveError) string {
	switch cause := cause.(type) {
	case ArchiveError_InvalidInput:
		return "archive: invalid input"
	case ArchiveError_InvalidData:
		return "archive: invalid data"
	case ArchiveError_LimitExceeded:
		return "archive: limit exceeded"
	case ArchiveError_Unsupported:
		return "archive: operation not supported"
	case ArchiveError_Failed:
		return cause.Message
	}
	return "archive: operation failed"
}

// Errors_Message_BigIntError is the Error message of BigIntError.
func Errors_Message_BigIntError(ctx *Execution, cause BigIntError) string {
	switch cause.(type) {
	case BigIntError_InvalidInput:
		return "big integer: invalid input"
	case BigIntError_InvalidData:
		return "big integer: invalid data"
	case BigIntError_LimitExceeded:
		return "big integer: limit exceeded"
	}
	return "big integer: operation failed"
}

// Errors_Message_BinaryError is the Error message of BinaryError.
func Errors_Message_BinaryError(ctx *Execution, cause BinaryError) string {
	switch cause.(type) {
	case BinaryError_InvalidInput:
		return "binary: invalid input"
	case BinaryError_OutOfRange:
		return "binary: value out of range"
	}
	return "binary: operation failed"
}

// Errors_Message_CollectionError is the Error message of CollectionError.
func Errors_Message_CollectionError(ctx *Execution, cause CollectionError) string {
	switch cause.(type) {
	case CollectionError_InvalidInput:
		return "collection: invalid input"
	case CollectionError_LimitExceeded:
		return "collection: limit exceeded"
	case CollectionError_OutOfRange:
		return "collection: value out of range"
	}
	return "collection: operation failed"
}

// Errors_Message_CommandError is the Error message of CommandError.
func Errors_Message_CommandError(ctx *Execution, cause CommandError) string {
	switch cause := cause.(type) {
	case CommandError_InvalidInput:
		return "command: invalid input"
	case CommandError_Unavailable:
		return "command: service unavailable"
	case CommandError_Timeout:
		return "command: operation timed out"
	case CommandError_OutputLimit:
		return "command: output limit exceeded"
	case CommandError_Failed:
		return cause.Message
	}
	return "command: operation failed"
}

// Errors_Message_CompressionError is the Error message of CompressionError.
func Errors_Message_CompressionError(ctx *Execution, cause CompressionError) string {
	switch cause := cause.(type) {
	case CompressionError_InvalidInput:
		return "compression: invalid input"
	case CompressionError_InvalidData:
		return "compression: invalid data"
	case CompressionError_LimitExceeded:
		return "compression: limit exceeded"
	case CompressionError_Unsupported:
		return "compression: operation not supported"
	case CompressionError_Failed:
		return cause.Message
	}
	return "compression: operation failed"
}

// Errors_Message_CryptoError is the Error message of CryptoError.
func Errors_Message_CryptoError(ctx *Execution, cause CryptoError) string {
	switch cause.(type) {
	case CryptoError_InvalidInput:
		return "cryptography: invalid input"
	case CryptoError_Unsupported:
		return "cryptography: operation not supported"
	case CryptoError_AuthenticationFailed:
		return "cryptography: authentication failed"
	}
	return "cryptography: operation failed"
}

// Errors_Message_CsvError is the Error message of CsvError.
func Errors_Message_CsvError(ctx *Execution, cause CsvError) string {
	switch cause.(type) {
	case CsvError_InvalidInput:
		return "CSV: invalid input"
	case CsvError_InvalidData:
		return "CSV: invalid data"
	case CsvError_LimitExceeded:
		return "CSV: limit exceeded"
	}
	return "CSV: operation failed"
}

// Errors_Message_EncodingError is the Error message of EncodingError.
func Errors_Message_EncodingError(ctx *Execution, cause EncodingError) string {
	switch cause.(type) {
	case EncodingError_InvalidInput:
		return "encoding: invalid input"
	case EncodingError_InvalidData:
		return "encoding: invalid data"
	case EncodingError_LimitExceeded:
		return "encoding: limit exceeded"
	}
	return "encoding: operation failed"
}

// Errors_Message_ExecutionError is the Error message of ExecutionError.
func Errors_Message_ExecutionError(ctx *Execution, cause ExecutionError) string {
	switch cause := cause.(type) {
	case ExecutionError_Timeout:
		return "task execution: operation timed out"
	case ExecutionError_Cancelled:
		return "task execution: operation cancelled"
	case ExecutionError_Crashed:
		return cause.Message
	}
	return "task execution: operation failed"
}

// Errors_Message_FileSystemError is the Error message of FileSystemError.
func Errors_Message_FileSystemError(ctx *Execution, cause FileSystemError) string {
	switch cause := cause.(type) {
	case FileSystemError_InvalidInput:
		return "filesystem: invalid input"
	case FileSystemError_InvalidData:
		return "filesystem: invalid data"
	case FileSystemError_LimitExceeded:
		return "filesystem: limit exceeded"
	case FileSystemError_NotFound:
		return "filesystem: file or directory not found"
	case FileSystemError_AlreadyExists:
		return "filesystem: already exists"
	case FileSystemError_NotEmpty:
		return "filesystem: directory not empty"
	case FileSystemError_PermissionDenied:
		return "filesystem: permission denied"
	case FileSystemError_Unsupported:
		return "filesystem: operation not supported"
	case FileSystemError_Closed:
		return "filesystem: resource is closed"
	case FileSystemError_Failed:
		return cause.Message
	}
	return "filesystem: operation failed"
}

// Errors_Message_HtmlError is the Error message of HtmlError.
func Errors_Message_HtmlError(ctx *Execution, cause HtmlError) string {
	switch cause.(type) {
	case HtmlError_InvalidInput:
		return "HTML: invalid input"
	case HtmlError_InvalidData:
		return "HTML: invalid data"
	case HtmlError_LimitExceeded:
		return "HTML: limit exceeded"
	}
	return "HTML: operation failed"
}

// Errors_Message_HttpError is the Error message of HttpError.
func Errors_Message_HttpError(ctx *Execution, cause HttpError) string {
	switch cause := cause.(type) {
	case HttpError_InvalidInput:
		return "HTTP: invalid input"
	case HttpError_InvalidData:
		return "HTTP: invalid data"
	case HttpError_LimitExceeded:
		return "HTTP: limit exceeded"
	case HttpError_PermissionDenied:
		return "HTTP: permission denied"
	case HttpError_Closed:
		return "HTTP: resource is closed"
	case HttpError_Timeout:
		return "HTTP: operation timed out"
	case HttpError_Failed:
		return cause.Message
	}
	return "HTTP: operation failed"
}

// Errors_Message_IoError is the Error message of IoError.
func Errors_Message_IoError(ctx *Execution, cause IoError) string {
	switch cause := cause.(type) {
	case IoError_Closed:
		return "I/O: resource is closed"
	case IoError_InvalidInput:
		return "I/O: invalid input"
	case IoError_Unavailable:
		return "I/O: service unavailable"
	case IoError_InvalidData:
		return "I/O: invalid data"
	case IoError_LimitExceeded:
		return "I/O: limit exceeded"
	case IoError_Failed:
		return cause.Message
	}
	return "I/O: operation failed"
}

// Errors_Message_JsonError is the Error message of JsonError.
func Errors_Message_JsonError(ctx *Execution, cause JsonError) string {
	switch cause.(type) {
	case JsonError_InvalidInput:
		return "JSON: invalid input"
	case JsonError_InvalidData:
		return "JSON: invalid data"
	case JsonError_LimitExceeded:
		return "JSON: limit exceeded"
	}
	return "JSON: operation failed"
}

// Errors_Message_LogError is the Error message of LogError.
func Errors_Message_LogError(ctx *Execution, cause LogError) string {
	switch cause := cause.(type) {
	case LogError_InvalidInput:
		return "logging: invalid input"
	case LogError_InvalidData:
		return "logging: invalid data"
	case LogError_LimitExceeded:
		return "logging: limit exceeded"
	case LogError_Closed:
		return "logging: resource is closed"
	case LogError_Io:
		return Errors_Message_IoError(ctx, cause.Cause)
	case LogError_FileSystem:
		return Errors_Message_FileSystemError(ctx, cause.Cause)
	}
	return "logging: operation failed"
}

// Errors_Message_NetworkError is the Error message of NetworkError.
func Errors_Message_NetworkError(ctx *Execution, cause NetworkError) string {
	switch cause := cause.(type) {
	case NetworkError_InvalidInput:
		return "network: invalid input"
	case NetworkError_InvalidData:
		return "network: invalid data"
	case NetworkError_LimitExceeded:
		return "network: limit exceeded"
	case NetworkError_PermissionDenied:
		return "network: permission denied"
	case NetworkError_Unsupported:
		return "network: operation not supported"
	case NetworkError_Closed:
		return "network: resource is closed"
	case NetworkError_Timeout:
		return "network: operation timed out"
	case NetworkError_Failed:
		return cause.Message
	}
	return "network: operation failed"
}

// Errors_Message_NumberError is the Error message of NumberError.
func Errors_Message_NumberError(ctx *Execution, cause NumberError) string {
	switch cause.(type) {
	case NumberError_InvalidInput:
		return "number: invalid input"
	case NumberError_InvalidData:
		return "number: invalid data"
	case NumberError_OutOfRange:
		return "number: value out of range"
	}
	return "number: operation failed"
}

// Errors_Message_PathError is the Error message of PathError.
func Errors_Message_PathError(ctx *Execution, cause PathError) string {
	switch cause.(type) {
	case PathError_InvalidInput:
		return "path: invalid input"
	}
	return "path: operation failed"
}

// Errors_Message_ProcessError is the Error message of ProcessError.
func Errors_Message_ProcessError(ctx *Execution, cause ProcessError) string {
	switch cause := cause.(type) {
	case ProcessError_InvalidInput:
		return "process: invalid input"
	case ProcessError_InvalidData:
		return "process: invalid data"
	case ProcessError_LimitExceeded:
		return "process: limit exceeded"
	case ProcessError_NotFound:
		return "process: not found"
	case ProcessError_AlreadyExists:
		return "process: already exists"
	case ProcessError_PermissionDenied:
		return "process: permission denied"
	case ProcessError_Unsupported:
		return "process: operation not supported"
	case ProcessError_Closed:
		return "process: resource is closed"
	case ProcessError_Failed:
		return cause.Message
	}
	return "process: operation failed"
}

// Errors_Message_RandomError is the Error message of RandomError.
func Errors_Message_RandomError(ctx *Execution, cause RandomError) string {
	switch cause := cause.(type) {
	case RandomError_InvalidInput:
		return "random: invalid input"
	case RandomError_LimitExceeded:
		return "random: limit exceeded"
	case RandomError_Failed:
		return cause.Message
	}
	return "random: operation failed"
}

// Errors_Message_RegexError is the Error message of RegexError.
func Errors_Message_RegexError(ctx *Execution, cause RegexError) string {
	switch cause.(type) {
	case RegexError_InvalidInput:
		return "regular expression: invalid input"
	case RegexError_InvalidData:
		return "regular expression: invalid data"
	case RegexError_LimitExceeded:
		return "regular expression: limit exceeded"
	}
	return "regular expression: operation failed"
}

// Errors_Message_StartError is the Error message of StartError.
func Errors_Message_StartError(ctx *Execution, cause StartError) string {
	switch cause.(type) {
	case StartError_Closed:
		return "scheduler: resource is closed"
	case StartError_Full:
		return "scheduler: capacity exhausted"
	case StartError_InvalidInput:
		return "scheduler: invalid input"
	}
	return "scheduler: operation failed"
}

// Errors_Message_StringError is the Error message of StringError.
func Errors_Message_StringError(ctx *Execution, cause StringError) string {
	switch cause := cause.(type) {
	case StringError_InvalidInput:
		return "string: invalid input"
	case StringError_OutOfRange:
		return "string: value out of range"
	case StringError_LimitExceeded:
		return "string: limit exceeded"
	case StringError_Failed:
		return cause.Message
	}
	return "string: operation failed"
}

// Errors_Message_SystemError is the Error message of SystemError.
func Errors_Message_SystemError(ctx *Execution, cause SystemError) string {
	switch cause := cause.(type) {
	case SystemError_InvalidInput:
		return "system: invalid input"
	case SystemError_InvalidData:
		return "system: invalid data"
	case SystemError_LimitExceeded:
		return "system: limit exceeded"
	case SystemError_NotFound:
		return "system: not found"
	case SystemError_AlreadyExists:
		return "system: already exists"
	case SystemError_PermissionDenied:
		return "system: permission denied"
	case SystemError_Unsupported:
		return "system: operation not supported"
	case SystemError_Closed:
		return "system: resource is closed"
	case SystemError_Failed:
		return cause.Message
	}
	return "system: operation failed"
}

// Errors_Message_TimeError is the Error message of TimeError.
func Errors_Message_TimeError(ctx *Execution, cause TimeError) string {
	switch cause.(type) {
	case TimeError_InvalidInput:
		return "time: invalid input"
	case TimeError_Closed:
		return "time: resource is closed"
	case TimeError_InvalidData:
		return "time: invalid data"
	case TimeError_OutOfRange:
		return "time: value out of range"
	}
	return "time: operation failed"
}

// Errors_Message_TlsError is the Error message of TlsError.
func Errors_Message_TlsError(ctx *Execution, cause TlsError) string {
	switch cause.(type) {
	case TlsError_InvalidInput:
		return "TLS: invalid input"
	case TlsError_InvalidData:
		return "TLS: invalid data"
	case TlsError_LimitExceeded:
		return "TLS: limit exceeded"
	case TlsError_AuthenticationFailed:
		return "TLS: authentication failed"
	}
	return "TLS: operation failed"
}

// Errors_Message_UrlError is the Error message of UrlError.
func Errors_Message_UrlError(ctx *Execution, cause UrlError) string {
	switch cause.(type) {
	case UrlError_InvalidInput:
		return "URL: invalid input"
	case UrlError_InvalidData:
		return "URL: invalid data"
	case UrlError_LimitExceeded:
		return "URL: limit exceeded"
	}
	return "URL: operation failed"
}

// Errors_Message_WebSocketError is the Error message of WebSocketError.
func Errors_Message_WebSocketError(ctx *Execution, cause WebSocketError) string {
	switch cause := cause.(type) {
	case WebSocketError_InvalidInput:
		return "WebSocket: invalid input"
	case WebSocketError_InvalidData:
		return "WebSocket: invalid data"
	case WebSocketError_LimitExceeded:
		return "WebSocket: limit exceeded"
	case WebSocketError_PermissionDenied:
		return "WebSocket: permission denied"
	case WebSocketError_Closed:
		return "WebSocket: resource is closed"
	case WebSocketError_Timeout:
		return "WebSocket: operation timed out"
	case WebSocketError_Failed:
		return cause.Message
	}
	return "WebSocket: operation failed"
}
