# One warning set for every C target. Warnings are errors from the first commit; there
# is no exemption list (plan section 7.2).
set(MS_C_WARNINGS
  -Wall -Wextra -Wpedantic -Werror
  -Wconversion -Wsign-conversion -Wshadow -Wvla -Wcast-qual -Wcast-align
  -Wstrict-prototypes -Wmissing-prototypes -Wundef)

# Adds the warning set and the shared include root to a target.
function(ms_target_defaults target)
  target_compile_options(${target} PRIVATE ${MS_C_WARNINGS})
  target_include_directories(${target} PRIVATE "${CMAKE_SOURCE_DIR}/src")
endfunction()

# The Windows C runtime marks fopen and friends deprecated; the C code uses the portable names.
if(WIN32)
  add_compile_definitions(_CRT_SECURE_NO_WARNINGS WIN32_LEAN_AND_MEAN)
endif()
