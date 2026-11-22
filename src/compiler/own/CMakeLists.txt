add_library(ms_own STATIC class.c own.c unused.c changes.c borrows.c uses.c moves.c closers.c bind.c live_expr.c live_set.c live_stmt.c places.c)
ms_target_defaults(ms_own)
target_link_libraries(ms_own PUBLIC ms_base ms_syntax ms_project ms_check)
