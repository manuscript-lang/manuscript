# The C style gate (documentation/contributing/c-style.md) as the CMake target `c-lint`: the flags (strict warnings from
# toolchain/c-warnings.txt and the include paths of every library) are generated here, so no script names a library,
# and toolchain/c-lint.sh keeps the policy (the pending list, the base-ref scoping, clang-tidy, the banned calls).
#   cmake -S . -B target/cmake/lint -G Ninja && C_LINT_BASE=<ref> cmake --build target/cmake/lint --target c-lint
file(STRINGS "${CMAKE_SOURCE_DIR}/toolchain/c-warnings.txt" _warnings)
set(_lint_includes src/runtime/include src/runtime/core src/runtime/tests/support src/compiler/include src/compiler/src src/compiler/src crates/ms-rt-abi/include
    src/runtime/tests src/runtime/third_party/llhttp/include src/runtime/third_party/mimalloc/include src/runtime/third_party/yyjson/include)
set(_lint_flags "-std=c11 ${_warnings}")
string(REPLACE ";" " " _lint_flags "${_lint_flags}")
# -Wcomma is clang-only, so it is not in the shared list.
string(APPEND _lint_flags " -Wcomma")
foreach(dir ${_lint_includes})
  string(APPEND _lint_flags " -I${dir}")
endforeach()
foreach(name ${MS_LIB_NAMES})
  foreach(dir ${MS_LIB_${name}_INCLUDES})
    string(APPEND _lint_flags " -isystem ${dir}")
  endforeach()
endforeach()
file(WRITE "${CMAKE_BINARY_DIR}/lint-flags.txt" "${_lint_flags}\n")
add_custom_target(c-lint
  COMMAND ${CMAKE_COMMAND} -E env MS_LINT_FLAGS=${CMAKE_BINARY_DIR}/lint-flags.txt
          sh -c "sh toolchain/c-lint.sh \"$C_LINT_BASE\""
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  USES_TERMINAL VERBATIM)
