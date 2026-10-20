/* Calls a generated closure through a real native frame. The post-call volatile
   use prevents a tail call, keeping the boundary observable to fault tracing. */
int64_t msrt_test_callback(const uint8_t *closure) {
  int64_t (*code)(const uint8_t *, int64_t);
  memcpy(&code, closure + 16, sizeof code);
  volatile int64_t result = code(closure, INT64_MAX);
  return result + 1;
}
