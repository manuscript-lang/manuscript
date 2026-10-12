package msruntime

import "embed"

// Sources is embedded so generated programs can be built without runtime downloads.
//
//go:embed values.go clone.go errors.go numeric.go collections.go tasks.go host.go background.go lifetime.go services.go synchronized.go http.go process.go library.go library_data.go library_formats.go library_crypto.go library_host.go library_net.go library_algorithms.go library_archive.go library_tools.go library_networking.go library_http_client.go library_http_server.go library_websocket.go library_tls.go profile.go library_collections.go library_string.go native_library_members.go library_fs.go library_fs_copy.go library_fs_glob.go library_watch.go library_path.go library_glob.go library_timers.go library_scheduled_timers.go library_system.go library_signals.go
var Sources embed.FS
