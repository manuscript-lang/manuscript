/* The std tests run no stop handler, so a stop request that runtime/std/process.c raises at its own process on Windows
 * reaches no one. Only the std tests link this: the entry tests link the real runtime/io/stop.c. */
#ifdef _WIN32
void ms_io_stop_raise(int signal_number);

void ms_io_stop_raise(int signal_number) { (void)signal_number; }
#endif
