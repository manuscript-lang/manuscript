# zlib 1.4, static. The sources are listed explicitly (the vendored tree has no CMake file).
add_library(zlib STATIC
  zlib/adler32.c zlib/compress.c zlib/crc32.c zlib/deflate.c zlib/gzclose.c zlib/gzlib.c zlib/gzread.c
  zlib/gzwrite.c zlib/infback.c zlib/inffast.c zlib/inflate.c zlib/inftrees.c zlib/trees.c zlib/uncompr.c
  zlib/zutil.c)
target_include_directories(zlib SYSTEM PUBLIC zlib)
if(NOT WIN32)
  target_compile_definitions(zlib PRIVATE _LARGEFILE64_SOURCE=1)
endif()
