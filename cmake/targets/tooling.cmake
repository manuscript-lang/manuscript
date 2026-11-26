# The interactive page `ms map --format html` fills with the fact model.
set(page_c ${MS_GEN}/page.c)
add_custom_command(
  OUTPUT ${page_c}
  COMMAND ${CMAKE_COMMAND} -DINPUT=${CMAKE_SOURCE_DIR}/src/tooling/data/page.html -DOUTPUT=${page_c} -DSYMBOL=ms_page_html
          -P ${CMAKE_SOURCE_DIR}/cmake/EmbedBlob.cmake
  DEPENDS ${CMAKE_SOURCE_DIR}/src/tooling/data/page.html ${CMAKE_SOURCE_DIR}/cmake/EmbedBlob.cmake
  COMMENT "Embedding page.html")
ms_library(ms_tooling tooling
  SOURCES
    lint_rules.c lint.c lint_text.c lint_effects.c lint_imports.c lint_unreachable.c lint_matches.c lint_syntax.c lint_calls.c
    lint_promises.c lint_recursion.c lint_terse.c lint_terse_stmts.c inspect.c inspect_document.c diagram.c facts.c
    flow.c views.c views_custom.c views_mark.c report.c diff.c review.c doc_comment.c decl_header.c guide.c guide_pages.c search_text.c html.c
    occurrence.c occurrence_types.c json_value.c findings.c snippet.c checked_input.c ${page_c}
  LINK ms_base ms_syntax ms_project ms_check ms_own)
