#include <stddef.h>
#include <stdio.h>

extern const size_t cpkt_native_layout[];
extern const size_t cpkt_native_layout_count;
extern const size_t cpkt_public_layout[];
extern const size_t cpkt_public_layout_count;

int main(void) {
  size_t i;
  if (cpkt_native_layout_count != cpkt_public_layout_count)
    return 1;
  for (i = 0; i < cpkt_native_layout_count; ++i) {
    if (cpkt_native_layout[i] != cpkt_public_layout[i]) {
      fprintf(stderr,
              "Public record size/alignment/offset mismatch at index %lu: %lu "
              "!= %lu\n",
              (unsigned long)i, (unsigned long)cpkt_public_layout[i],
              (unsigned long)cpkt_native_layout[i]);
      return 1;
    }
  }
  return 0;
}
