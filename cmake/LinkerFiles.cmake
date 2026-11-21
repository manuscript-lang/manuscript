# The files `ms_build_link` links with (`MsLinkOptions.files`, compiler/include/ms/build_link.h), gathered for this host into
# MS_LINKER_OUT (default target/ms-linker). Included by BuildRuntime.cmake for `-DMS_MODE=linker`, which has set host_os,
# arch, exe_suffix and MS_ROOT.
#   Linux: crt1.o crti.o crtn.o libc.a of musl (static links), libunwind.a, and glibc.symbols (the glibc 2.28 stand-ins).
#   Windows: crt2.o, the mingw-w64 libraries and import libraries, and the compiler-rt builtins as libclang_rt.builtins.a.
#   macOS: nothing; the SDK stubs are generated from the object being linked.
if(NOT MS_LINKER_OUT)
  set(MS_LINKER_OUT "${MS_ROOT}/target/ms-linker")
endif()
file(REMOVE_RECURSE "${MS_LINKER_OUT}")
file(MAKE_DIRECTORY "${MS_LINKER_OUT}")

# Copies `from` to the linker folder as `name`, failing with `what` when it is missing.
function(take from name what)
  if(NOT EXISTS "${from}")
    message(FATAL_ERROR "no ${what} at ${from}")
  endif()
  file(COPY_FILE "${from}" "${MS_LINKER_OUT}/${name}")
endfunction()

if(host_os STREQUAL "Linux")
  # musl's startup files and libc: MS_MUSL_LIB, else the distribution's `<arch>-linux-musl` folder.
  if(DEFINED ENV{MS_MUSL_LIB})
    set(musl "$ENV{MS_MUSL_LIB}")
  else()
    set(musl "/usr/lib/${arch}-linux-musl")
  endif()
  foreach(name crt1.o crti.o crtn.o libc.a)
    take("${musl}/${name}" "${name}" "musl ${name} (set MS_MUSL_LIB to the folder holding it)")
  endforeach()
  # The unwinder: MS_LIBUNWIND, else LLVM's libunwind.a if the compiler finds one, else GCC's libgcc_eh.a (same _Unwind_ API).
  if(DEFINED ENV{MS_LIBUNWIND})
    set(unwind "$ENV{MS_LIBUNWIND}")
  else()
    execute_process(COMMAND clang -print-file-name=libunwind.a OUTPUT_VARIABLE unwind OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT IS_ABSOLUTE "${unwind}" OR NOT EXISTS "${unwind}")
      execute_process(COMMAND gcc -print-file-name=libgcc_eh.a OUTPUT_VARIABLE unwind OUTPUT_STRIP_TRAILING_WHITESPACE)
    endif()
  endif()
  take("${unwind}" libunwind.a "unwinder (set MS_LIBUNWIND to an LLVM libunwind.a or GCC libgcc_eh.a)")
  take("${MS_ROOT}/toolchain/glibc/${arch}.symbols" glibc.symbols "glibc symbol table")
elseif(host_os STREQUAL "Windows")
  if(DEFINED ENV{MS_MINGW})
    set(mingw "$ENV{MS_MINGW}")
  else()
    set(mingw "${MS_ROOT}/target/llvm-bundle/mingw")
  endif()
  set(lib "${mingw}/${arch}-w64-mingw32/lib")
  foreach(name crt2.o libmingw32.a libmingwex.a libmoldname.a libunwind.a libucrt.a libmsvcrt.a libkernel32.a libadvapi32.a
               libbcrypt.a libcrypt32.a libdbghelp.a libntdll.a libsecur32.a libuserenv.a libiphlpapi.a libpsapi.a
               libole32.a libws2_32.a libuser32.a libshell32.a libsynchronization.a)
    take("${lib}/${name}" "${name}" "mingw-w64 ${name} (run toolchain/fetch-mingw.sh, or set MS_MINGW)")
  endforeach()
  # The compiler runtime: stack probes (___chkstk_ms) the runtime and the C libraries call.
  file(GLOB builtins "${mingw}/lib/clang/*/lib/windows/libclang_rt.builtins-${arch}.a")
  list(GET builtins 0 builtin)
  take("${builtin}" libclang_rt.builtins.a "compiler-rt builtins")
endif()
message(STATUS "linker files: ${MS_LINKER_OUT}")
