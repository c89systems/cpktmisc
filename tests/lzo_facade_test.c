#include <cpkt/lzo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);          \
      return 1;                                                                \
    }                                                                          \
  } while (0)

static void progress(cpkt_lzo_lzo_callback_t *callbacks,
                     cpkt_lzo_lzo_uint input, cpkt_lzo_lzo_uint output,
                     int state) {
  (void)input;
  (void)output;
  (void)state;
  ++*(int *)callbacks->user1;
}

int main(void) {
  const unsigned char input[] = "full LZO C89 compression surface";
  unsigned char encoded[512], decoded[128];
  void *work;
  cpkt_lzo_lzo_uint size, length;
  CPKT_LZO_lzo_uint64_t maximum;
  CPKT_LZO_lzo_int64_t negative;
  cpkt_lzo_lzo_align_t alignment;
  cpkt_lzo_lzo_callback_t callbacks;
  int calls;
  memset(&callbacks, 0, sizeof(callbacks));
  CHECK(CPKT_LZO_lzo_init() == CPKT_LZO_LZO_E_OK);
  CHECK(cpkt_lzo__lzo_config_check() == CPKT_LZO_LZO_E_OK);
  maximum = CPKT_LZO_LZO_UINT64_MAX;
  CHECK(maximum.lo == 4294967295U && maximum.hi == 4294967295U);
  alignment.a10 = maximum;
  CHECK(alignment.a10.hi == 4294967295U);
  negative = CPKT_LZO_LZO_INT64_C(-123);
  CHECK(negative.lo == 4294967173U && negative.hi == -1);
  work = CPKT_LZO_lzo_malloc(CPKT_LZO_LZO1X_1_MEM_COMPRESS);
  CHECK(work != NULL);
  size = sizeof(encoded);
  CHECK(cpkt_lzo_lzo1x_1_compress(input, sizeof(input), encoded, &size, work) ==
        CPKT_LZO_LZO_E_OK);
  length = sizeof(decoded);
  CHECK(cpkt_lzo_lzo1x_decompress_safe(encoded, size, decoded, &length, NULL) ==
        CPKT_LZO_LZO_E_OK);
  CHECK(length == sizeof(input) && memcmp(decoded, input, sizeof(input)) == 0);
  length = sizeof(decoded);
  CHECK(cpkt_lzo_lzo1x_decompress_asm_fast_safe(encoded, size, decoded, &length,
                                                NULL) == CPKT_LZO_LZO_E_OK);
  CHECK(length == sizeof(input) && memcmp(decoded, input, sizeof(input)) == 0);
  length = 1;
  CHECK(cpkt_lzo_lzo1x_decompress_safe(encoded, size, decoded, &length, NULL) ==
        CPKT_LZO_LZO_E_OUTPUT_OVERRUN);
  CHECK(cpkt_lzo_lzo_crc32(0, (const unsigned char *)"123456789", 9) ==
        0xcbf43926U);
  CPKT_LZO_lzo_free(work);
  calls = 0;
  callbacks.user1 = &calls;
  callbacks.nprogress = progress;
  work = CPKT_LZO_lzo_malloc(CPKT_LZO_LZO1X_999_MEM_COMPRESS);
  CHECK(work != NULL);
  size = sizeof(encoded);
  CHECK(cpkt_lzo_lzo1x_999_compress_level(input, sizeof(input), encoded, &size,
                                          work, NULL, 0, &callbacks,
                                          9) == CPKT_LZO_LZO_E_OK);
  CHECK(calls > 0);
  CPKT_LZO_lzo_free(work);
  return 0;
}
