ms_library(ms_lsp lsp
  SOURCES
    lsp_actions.c lsp_analysis.c lsp_command.c lsp_completion.c lsp_completion_imports.c lsp_frame.c lsp_input.c lsp_nav.c lsp_nav_fallback.c lsp_semantic.c lsp_signature.c lsp_supervisor.c lsp_symbols.c lsp_sync.c lsp_text.c lsp_uri.c lsp_workspace.c
  LINK ms_base ms_syntax ms_project ms_check ms_own ms_tooling)
file(STRINGS ${CMAKE_SOURCE_DIR}/.msversion MS_VERSION_TEXT LIMIT_COUNT 1)
target_compile_definitions(ms_lsp PRIVATE MS_VERSION="${MS_VERSION_TEXT}")
