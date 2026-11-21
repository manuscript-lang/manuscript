add_library(ms_syntax STATIC
  diag_codes.c diag_json.c
  format.c format_compact.c format_cuts.c format_group.c format_import.c format_layout.c format_render.c
  format_spacing.c format_syntax.c format_text.c format_tree.c
  lex.c lex_continue.c lex_layout.c lex_scan.c lex_text.c lex_token.c lex_unicode.c
  parse.c parse_bind.c parse_core.c parse_decl.c parse_decl_item.c parse_expr.c parse_primary.c parse_stmt.c
  parse_tables.c parse_text.c parse_type.c
  partial.c partial_lines.c partial_recover.c
  token.c walk.c)
ms_target_defaults(ms_syntax)
target_link_libraries(ms_syntax PUBLIC ms_base)
