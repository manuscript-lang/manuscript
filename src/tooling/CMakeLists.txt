# The interactive page `ms diagram --format html` fills with the fact model.
set(page_c ${CMAKE_CURRENT_BINARY_DIR}/page.c)
add_custom_command(
  OUTPUT ${page_c}
  COMMAND ${CMAKE_COMMAND} -DINPUT=${CMAKE_CURRENT_SOURCE_DIR}/data/page.html -DOUTPUT=${page_c} -DSYMBOL=ms_page_html
          -P ${PROJECT_SOURCE_DIR}/cmake/EmbedBlob.cmake
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/data/page.html ${PROJECT_SOURCE_DIR}/cmake/EmbedBlob.cmake
  COMMENT "Embedding page.html")
add_library(ms_tooling STATIC lint_rules.c lint.c lint_text.c lint_effects.c lint_imports.c lint_unreachable.c lint_matches.c lint_calls.c lint_promises.c lint_recursion.c lint_terse.c lint_terse_stmts.c inspect.c diagram.c facts.c flow.c views.c report.c diff.c review.c doc_comment.c guide.c guide_pages.c html.c ${page_c})
ms_target_defaults(ms_tooling)
target_include_directories(ms_tooling PRIVATE ${PROJECT_SOURCE_DIR}/src)
target_link_libraries(ms_tooling PUBLIC ms_base ms_syntax ms_check)
