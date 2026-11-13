#include <stdio.h>
#include "ordmap.h"
ORDMAP(CountMap, long)
int main(void) {
  CountMap m = {0}; long x = 12345;
  for (long i = 0; i < 2000000; i++) { x = (x * 1103515245 + 12345) % 2147483648; long k = x % 50000; (*CountMap_at(&m, k))++; }
  long best = 0, hits = 0;
  for (long i = 0; i < 2000000; i++) { x = (x * 1103515245 + 12345) % 2147483648; if (CountMap_find(&m, x % 100000)) hits++; }
  for (size_t i = 0; i < m.used; i++) if (m.slots[i].hash && m.slots[i].value > best) best = m.slots[i].value;
  printf("%zu %ld %ld\n", m.len, best, hits); return 0;
}
