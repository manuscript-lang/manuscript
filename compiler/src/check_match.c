/* `match` expressions and patterns in function bodies (the Rust checker's match_expression and
 * pattern checks). A `match` it does not handle leaves the function unchecked. */
#include "check_body.h"

MsTy ms_body_match(MsBody *b, const MsExpr *e, MsTy expected) {
    (void)e;
    (void)expected;
    return ms_body_unsupported(b);
}
