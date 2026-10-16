//go:build !linux && !darwin

package hostos

import "os"

// StatInfo reports no native fields on this host.
func StatInfo(os.FileInfo) Stat { return Stat{} }
