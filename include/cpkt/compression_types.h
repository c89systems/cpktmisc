#ifndef CPKT_COMPRESSION_TYPES_H
#define CPKT_COMPRESSION_TYPES_H
#include <limits.h>

typedef char cpkt_compression_word_sizes
    [(CHAR_BIT == 8 && sizeof(unsigned int) == 4 && sizeof(int) == 4) ? 1 : -1];

/** Unsigned 64-bit value as two C89 unsigned 32-bit words, low word first. */
typedef struct {
  unsigned int lo;
  unsigned int hi;
} cpkt_compression_u64;

/** Signed two's-complement 64-bit value; hi is the signed upper word. */
typedef struct {
  unsigned int lo;
  int hi;
} cpkt_compression_i64;

#endif
