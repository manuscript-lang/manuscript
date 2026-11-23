# Fills the startup-files directory (MS_FILES) next to ms; run after each build by MsRuntimePackage.cmake.
#   -DFILES=<dir> -DSOURCE_DIR=<repo> -DOS=<Linux|Darwin|Windows> -DARCH=<processor>
#   -DMUSL_SYSROOT=<the musl sysroot of cmake/MsSysroot.cmake> -DMINGW_DIR=<llvm-mingw root> -DCOMPILER=<the C compiler>
# Linux gets the glibc export table (and the musl and unwinder files for `--static` and the unwinder input);
# Windows gets the mingw-w64 startup object and libraries; macOS needs only the directory (the SDK stubs are
# made there on demand). A file that cannot be found is reported once and skipped.
cmake_minimum_required(VERSION 3.25)
file(MAKE_DIRECTORY "${FILES}")

if(ARCH MATCHES "^(aarch64|arm64|ARM64)$")
  set(arch aarch64)
else()
  set(arch x86_64)
endif()

function(ms_copy_file from name)
  if(EXISTS "${from}")
    file(COPY_FILE "${from}" "${FILES}/${name}" ONLY_IF_DIFFERENT)
  else()
    message(WARNING "startup files: ${name} not found at ${from}")
  endif()
endfunction()

# The musl objects ship zlib-compressed debug sections, which the pinned lld (built without zlib) cannot read: drop them.
function(ms_strip_debug name)
  find_program(strip NAMES llvm-strip strip)
  if(NOT strip)
    message(WARNING "startup files: no strip tool, ${name} keeps its compressed debug sections")
    return()
  endif()
  execute_process(COMMAND "${strip}" --strip-debug "${FILES}/${name}" RESULT_VARIABLE status ERROR_VARIABLE err)
  if(NOT status EQUAL 0)
    message(FATAL_ERROR "startup files: cannot strip debug sections from ${name}: ${err}")
  endif()
endfunction()

if(OS STREQUAL "Linux")
  ms_copy_file("${SOURCE_DIR}/toolchain/glibc/${arch}.symbols" glibc.symbols)
  foreach(name crt1.o crti.o crtn.o libc.a libunwind.a)
    ms_copy_file("${MUSL_SYSROOT}/usr/lib/${name}" ${name})
    if(EXISTS "${FILES}/${name}")
      ms_strip_debug(${name})
    endif()
  endforeach()
  # aarch64 long double is 128-bit: converting it needs the soft-float builtins (`__trunctfdf2`), which lld links from here.
  if(arch STREQUAL "aarch64" AND COMPILER)
    execute_process(COMMAND "${COMPILER}" --print-libgcc-file-name OUTPUT_VARIABLE libgcc OUTPUT_STRIP_TRAILING_WHITESPACE)
    ms_copy_file("${libgcc}" libgcc.a)
  endif()
elseif(OS STREQUAL "Windows")
  # MINGW_DIR is an MSYS2 toolchain prefix (`<msys64>/clang64`: lib/ holds crt2.o and the libraries) or an llvm-mingw
  # release (`<dir>/<arch>-w64-mingw32/lib`).
  set(lib "${MINGW_DIR}/${arch}-w64-mingw32/lib")
  if(NOT IS_DIRECTORY "${lib}")
    set(lib "${MINGW_DIR}/lib")
  endif()
  foreach(name crt2.o libmingw32.a libunwind.a libmoldname.a libmingwex.a libucrt.a libadvapi32.a libbcrypt.a
          libcrypt32.a libdbghelp.a libntdll.a libsecur32.a libshell32.a libuser32.a libuserenv.a libiphlpapi.a
          libpsapi.a libole32.a libws2_32.a libsynchronization.a libkernel32.a)
    ms_copy_file("${lib}/${name}" ${name})
  endforeach()
  file(GLOB builtins "${MINGW_DIR}/lib/clang/*/lib/windows/libclang_rt.builtins-${arch}.a"
       "${MINGW_DIR}/lib/clang/*/lib/windows/libclang_rt.builtins-x86_64.a")
  if(builtins)
    list(GET builtins 0 builtin)
    ms_copy_file("${builtin}" libclang_rt.builtins.a)
  else()
    message(WARNING "startup files: libclang_rt.builtins.a not found under ${MINGW_DIR}/lib/clang")
  endif()
endif()
