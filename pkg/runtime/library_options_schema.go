package msruntime

// Native option-field representations; checked against the pinned stdlib source.
var nativeOptionRecords = map[string]map[string]string{
	"@std/ArchiveLimits":     {"max_entries": "Int", "max_entry_bytes": "Int", "max_total_bytes": "Int"},
	"@std/CopyOptions":       {"max_bytes": "Int", "max_entries": "Int"},
	"@std/GlobOptions":       {"max_entries": "Int", "max_results": "Int"},
	"@std/HtmlLimits":        {"max_bytes": "Int", "max_depth": "Int", "max_nodes": "Int"},
	"@std/HttpClientOptions": {"idle_timeout": "Duration", "max_header_bytes": "Int", "max_idle_connections": "Int", "max_redirects": "Int"},
	"@std/HttpServerOptions": {"tls": "TlsOptions", "grace": "Duration", "max_body_bytes": "Int", "max_header_bytes": "Int", "max_requests": "Int", "max_response_bytes": "Int", "timeout": "Duration"},
	"@std/JsonLimits":        {"max_bytes": "Int", "max_depth": "Int", "max_values": "Int"},
	"@std/WebSocketOptions":  {"max_message_bytes": "Int", "timeout": "Duration"},
}
