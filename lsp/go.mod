module manuscript-lsp-server

go 1.20 // Or your project's Go version

require (
	golang.org/x/tools v0.10.0 // For LSP components
	// Add a placeholder require for the actual internal parser package.
	// The user will need to replace 'your_project_module/internal/manuscript/parser' 
	// with the actual module path if it's different.
	your_project_module/internal/manuscript/parser v0.0.0-unpublished
)

// Use a replace directive to point to the local copy of the internal parser.
// This assumes 'internal' is a directory at the same level as 'lsp'.
replace your_project_module/internal/manuscript/parser => ../internal/manuscript/parser
