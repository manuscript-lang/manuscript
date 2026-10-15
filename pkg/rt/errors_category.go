// Code generated from the shared error cases of std_types_gen.go; see TestErrorCategoryCoverage. DO NOT EDIT.

package rt

// errorCategorized is implemented by the standard error cases that have a
// shared ErrorCategory. Cases without one (Failed, OutputLimit, ...) do not
// implement it.
type errorCategorized interface{ errorCategory() ErrorCategory }

func (ArchiveError_InvalidInput) errorCategory() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (ArchiveError_InvalidData) errorCategory() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (ArchiveError_LimitExceeded) errorCategory() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (ArchiveError_Unsupported) errorCategory() ErrorCategory   { return ErrorCategory_Unsupported{} }
func (BigIntError_InvalidInput) errorCategory() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (BigIntError_InvalidData) errorCategory() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (BigIntError_LimitExceeded) errorCategory() ErrorCategory  { return ErrorCategory_LimitExceeded{} }
func (BinaryError_InvalidInput) errorCategory() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (CollectionError_InvalidInput) errorCategory() ErrorCategory {
	return ErrorCategory_InvalidInput{}
}
func (CollectionError_LimitExceeded) errorCategory() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (CompressionError_InvalidInput) errorCategory() ErrorCategory {
	return ErrorCategory_InvalidInput{}
}
func (CompressionError_InvalidData) errorCategory() ErrorCategory { return ErrorCategory_InvalidData{} }
func (CompressionError_LimitExceeded) errorCategory() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (CompressionError_Unsupported) errorCategory() ErrorCategory { return ErrorCategory_Unsupported{} }
func (CryptoError_InvalidInput) errorCategory() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (CryptoError_Unsupported) errorCategory() ErrorCategory      { return ErrorCategory_Unsupported{} }
func (CsvError_InvalidInput) errorCategory() ErrorCategory        { return ErrorCategory_InvalidInput{} }
func (CsvError_InvalidData) errorCategory() ErrorCategory         { return ErrorCategory_InvalidData{} }
func (CsvError_LimitExceeded) errorCategory() ErrorCategory       { return ErrorCategory_LimitExceeded{} }
func (EncodingError_InvalidInput) errorCategory() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (EncodingError_InvalidData) errorCategory() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (EncodingError_LimitExceeded) errorCategory() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (FileSystemError_InvalidInput) errorCategory() ErrorCategory {
	return ErrorCategory_InvalidInput{}
}
func (FileSystemError_InvalidData) errorCategory() ErrorCategory { return ErrorCategory_InvalidData{} }
func (FileSystemError_LimitExceeded) errorCategory() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (FileSystemError_NotFound) errorCategory() ErrorCategory { return ErrorCategory_NotFound{} }
func (FileSystemError_AlreadyExists) errorCategory() ErrorCategory {
	return ErrorCategory_AlreadyExists{}
}
func (FileSystemError_PermissionDenied) errorCategory() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (FileSystemError_Unsupported) errorCategory() ErrorCategory { return ErrorCategory_Unsupported{} }
func (FileSystemError_Closed) errorCategory() ErrorCategory      { return ErrorCategory_Closed{} }
func (HtmlError_InvalidInput) errorCategory() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (HtmlError_InvalidData) errorCategory() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (HtmlError_LimitExceeded) errorCategory() ErrorCategory     { return ErrorCategory_LimitExceeded{} }
func (HttpError_InvalidInput) errorCategory() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (HttpError_InvalidData) errorCategory() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (HttpError_LimitExceeded) errorCategory() ErrorCategory     { return ErrorCategory_LimitExceeded{} }
func (HttpError_PermissionDenied) errorCategory() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (HttpError_Closed) errorCategory() ErrorCategory           { return ErrorCategory_Closed{} }
func (HttpError_Timeout) errorCategory() ErrorCategory          { return ErrorCategory_Timeout{} }
func (IoError_Closed) errorCategory() ErrorCategory             { return ErrorCategory_Closed{} }
func (IoError_InvalidInput) errorCategory() ErrorCategory       { return ErrorCategory_InvalidInput{} }
func (IoError_Unavailable) errorCategory() ErrorCategory        { return ErrorCategory_Unavailable{} }
func (IoError_InvalidData) errorCategory() ErrorCategory        { return ErrorCategory_InvalidData{} }
func (IoError_LimitExceeded) errorCategory() ErrorCategory      { return ErrorCategory_LimitExceeded{} }
func (JsonError_InvalidInput) errorCategory() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (JsonError_InvalidData) errorCategory() ErrorCategory      { return ErrorCategory_InvalidData{} }
func (JsonError_LimitExceeded) errorCategory() ErrorCategory    { return ErrorCategory_LimitExceeded{} }
func (LogError_InvalidInput) errorCategory() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (LogError_InvalidData) errorCategory() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (LogError_LimitExceeded) errorCategory() ErrorCategory     { return ErrorCategory_LimitExceeded{} }
func (LogError_Closed) errorCategory() ErrorCategory            { return ErrorCategory_Closed{} }
func (NetworkError_InvalidInput) errorCategory() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (NetworkError_InvalidData) errorCategory() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (NetworkError_LimitExceeded) errorCategory() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (NetworkError_PermissionDenied) errorCategory() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (NetworkError_Unsupported) errorCategory() ErrorCategory   { return ErrorCategory_Unsupported{} }
func (NetworkError_Closed) errorCategory() ErrorCategory        { return ErrorCategory_Closed{} }
func (NetworkError_Timeout) errorCategory() ErrorCategory       { return ErrorCategory_Timeout{} }
func (NumberError_InvalidInput) errorCategory() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (NumberError_InvalidData) errorCategory() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (PathError_InvalidInput) errorCategory() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (CommandError_InvalidInput) errorCategory() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (CommandError_Unavailable) errorCategory() ErrorCategory   { return ErrorCategory_Unavailable{} }
func (CommandError_Timeout) errorCategory() ErrorCategory       { return ErrorCategory_Timeout{} }
func (ProcessError_InvalidInput) errorCategory() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (ProcessError_InvalidData) errorCategory() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (ProcessError_LimitExceeded) errorCategory() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (ProcessError_NotFound) errorCategory() ErrorCategory      { return ErrorCategory_NotFound{} }
func (ProcessError_AlreadyExists) errorCategory() ErrorCategory { return ErrorCategory_AlreadyExists{} }
func (ProcessError_PermissionDenied) errorCategory() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (ProcessError_Unsupported) errorCategory() ErrorCategory  { return ErrorCategory_Unsupported{} }
func (ProcessError_Closed) errorCategory() ErrorCategory       { return ErrorCategory_Closed{} }
func (RandomError_InvalidInput) errorCategory() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (RandomError_LimitExceeded) errorCategory() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (RegexError_InvalidInput) errorCategory() ErrorCategory   { return ErrorCategory_InvalidInput{} }
func (RegexError_InvalidData) errorCategory() ErrorCategory    { return ErrorCategory_InvalidData{} }
func (RegexError_LimitExceeded) errorCategory() ErrorCategory  { return ErrorCategory_LimitExceeded{} }
func (StringError_InvalidInput) errorCategory() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (StringError_LimitExceeded) errorCategory() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (SystemError_InvalidInput) errorCategory() ErrorCategory  { return ErrorCategory_InvalidInput{} }
func (SystemError_InvalidData) errorCategory() ErrorCategory   { return ErrorCategory_InvalidData{} }
func (SystemError_LimitExceeded) errorCategory() ErrorCategory { return ErrorCategory_LimitExceeded{} }
func (SystemError_NotFound) errorCategory() ErrorCategory      { return ErrorCategory_NotFound{} }
func (SystemError_AlreadyExists) errorCategory() ErrorCategory { return ErrorCategory_AlreadyExists{} }
func (SystemError_PermissionDenied) errorCategory() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (SystemError_Unsupported) errorCategory() ErrorCategory     { return ErrorCategory_Unsupported{} }
func (SystemError_Closed) errorCategory() ErrorCategory          { return ErrorCategory_Closed{} }
func (ExecutionError_Timeout) errorCategory() ErrorCategory      { return ErrorCategory_Timeout{} }
func (StartError_Closed) errorCategory() ErrorCategory           { return ErrorCategory_Closed{} }
func (StartError_InvalidInput) errorCategory() ErrorCategory     { return ErrorCategory_InvalidInput{} }
func (TimeError_InvalidInput) errorCategory() ErrorCategory      { return ErrorCategory_InvalidInput{} }
func (TimeError_Closed) errorCategory() ErrorCategory            { return ErrorCategory_Closed{} }
func (TimeError_InvalidData) errorCategory() ErrorCategory       { return ErrorCategory_InvalidData{} }
func (TlsError_InvalidInput) errorCategory() ErrorCategory       { return ErrorCategory_InvalidInput{} }
func (TlsError_InvalidData) errorCategory() ErrorCategory        { return ErrorCategory_InvalidData{} }
func (TlsError_LimitExceeded) errorCategory() ErrorCategory      { return ErrorCategory_LimitExceeded{} }
func (UrlError_InvalidInput) errorCategory() ErrorCategory       { return ErrorCategory_InvalidInput{} }
func (UrlError_InvalidData) errorCategory() ErrorCategory        { return ErrorCategory_InvalidData{} }
func (UrlError_LimitExceeded) errorCategory() ErrorCategory      { return ErrorCategory_LimitExceeded{} }
func (WebSocketError_InvalidInput) errorCategory() ErrorCategory { return ErrorCategory_InvalidInput{} }
func (WebSocketError_InvalidData) errorCategory() ErrorCategory  { return ErrorCategory_InvalidData{} }
func (WebSocketError_LimitExceeded) errorCategory() ErrorCategory {
	return ErrorCategory_LimitExceeded{}
}
func (WebSocketError_PermissionDenied) errorCategory() ErrorCategory {
	return ErrorCategory_PermissionDenied{}
}
func (WebSocketError_Closed) errorCategory() ErrorCategory  { return ErrorCategory_Closed{} }
func (WebSocketError_Timeout) errorCategory() ErrorCategory { return ErrorCategory_Timeout{} }
