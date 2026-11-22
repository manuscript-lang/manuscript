# The runtime natives' parameter lists, generated from the ms-sig comments of src/runtime.
set(native_sigs ${CMAKE_CURRENT_BINARY_DIR}/native_sigs.c)
file(GLOB_RECURSE runtime_headers CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/src/runtime/*.h)
add_custom_command(
  OUTPUT ${native_sigs}
  COMMAND ${CMAKE_COMMAND} -DSRC_DIR=${PROJECT_SOURCE_DIR}/src/runtime -DOUTPUT=${native_sigs}
          -P ${PROJECT_SOURCE_DIR}/cmake/EmbedNativeSigs.cmake
  DEPENDS ${runtime_headers} ${PROJECT_SOURCE_DIR}/cmake/EmbedNativeSigs.cmake
  COMMENT "Generating native signatures")
add_library(ms_lower STATIC lower_types.c lower_scope.c lower_func.c lower_expr.c lower_stmt.c lower_call.c lower_native.c lower_extern.c lower_conv.c lower_for.c lower_close.c lower_parts.c lower_temp.c lower_text.c lower_match.c lower_list.c lower_iflet.c lower_closure.c lower_funcval.c lower_default.c lower_glue.c lower_result.c lower_tests.c lower_entry.c native_sig.c ${native_sigs})
ms_target_defaults(ms_lower)
target_link_libraries(ms_lower PUBLIC ms_base ms_syntax ms_check ms_own ms_mir)
