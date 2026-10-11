#include <cpkt/zstd.h>
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

static void *allocate(void *data, size_t size) {
  ++*(int *)data;
  return malloc(size);
}
static void release(void *data, void *address) {
  if (address) {
    --*(int *)data;
    free(address);
  }
}

int main(void) {
  const char input[] = "full zstd streaming and frame interfaces";
  const unsigned char wide_frame[] = {0x28, 0xb5, 0x2f, 0xfd, 0xe0, 123, 0,
                                      0,    0,    5,    0,    0,    0};
  char encoded[512], decoded[128];
  size_t size, status, produced;
  cpkt_compression_u64 content_size;
  cpkt_zstd_ZSTD_FrameHeader frame;
  cpkt_zstd_ZSTD_CCtx *encoder;
  cpkt_zstd_ZSTD_DCtx *decoder;
  cpkt_zstd_ZSTD_inBuffer source;
  cpkt_zstd_ZSTD_outBuffer sink;
  cpkt_zstd_ZSTD_customMem memory;
  int allocations;
  size = cpkt_zstd_ZSTD_compress(encoded, sizeof(encoded), input, sizeof(input),
                                 3);
  CHECK(!cpkt_zstd_ZSTD_isError(size));
  CHECK(cpkt_zstd_ZSTD_decompress(decoded, sizeof(decoded), encoded, size) ==
        sizeof(input));
  CHECK(memcmp(decoded, input, sizeof(input)) == 0);
  content_size = cpkt_zstd_ZSTD_getFrameContentSize(encoded, size);
  CHECK(content_size.lo == sizeof(input) && content_size.hi == 0);
  content_size =
      cpkt_zstd_ZSTD_getFrameContentSize(wide_frame, sizeof(wide_frame));
  CHECK(content_size.lo == 123 && content_size.hi == 5);
  CHECK(cpkt_zstd_ZSTD_getFrameHeader(&frame, encoded, size) == 0);
  CHECK(frame.frameContentSize.lo == sizeof(input) &&
        frame.frameContentSize.hi == 0);
  CHECK(cpkt_zstd_ZSTD_findFrameCompressedSize(encoded, size) == size);
  CHECK(cpkt_zstd_ZSTD_isError(
      cpkt_zstd_ZSTD_decompress(decoded, sizeof(decoded), "bad", 3)));
  content_size = cpkt_zstd_ZSTD_getFrameContentSize("bad", 3);
  CHECK(content_size.lo == CPKT_ZSTD_ZSTD_CONTENTSIZE_ERROR.lo &&
        content_size.hi == CPKT_ZSTD_ZSTD_CONTENTSIZE_ERROR.hi);

  allocations = 0;
  memory.customAlloc = allocate;
  memory.customFree = release;
  memory.opaque = &allocations;
  encoder = cpkt_zstd_ZSTD_createCCtx_advanced(memory);
  decoder = cpkt_zstd_ZSTD_createDCtx();
  CHECK(encoder != NULL && decoder != NULL);
  source.src = input;
  source.size = sizeof(input);
  source.pos = 0;
  sink.dst = encoded;
  sink.size = 1;
  sink.pos = 0;
  produced = 0;
  do {
    status = cpkt_zstd_ZSTD_compressStream2(encoder, &sink, &source,
                                            CPKT_ZSTD_ZSTD_e_end);
    CHECK(!cpkt_zstd_ZSTD_isError(status));
    produced += sink.pos;
    CHECK(produced < sizeof(encoded));
    sink.dst = encoded + produced;
    sink.pos = 0;
  } while (status != 0);
  CHECK(source.pos == sizeof(input));
  source.src = encoded;
  source.size = produced;
  source.pos = 0;
  sink.dst = decoded;
  sink.size = 1;
  sink.pos = 0;
  produced = 0;
  do {
    status = cpkt_zstd_ZSTD_decompressStream(decoder, &sink, &source);
    CHECK(!cpkt_zstd_ZSTD_isError(status));
    produced += sink.pos;
    CHECK(produced < sizeof(decoded));
    sink.dst = decoded + produced;
    sink.pos = 0;
  } while (status != 0);
  CHECK(produced == sizeof(input) && source.pos == source.size);
  CHECK(memcmp(decoded, input, sizeof(input)) == 0);
  CHECK(cpkt_zstd_ZSTD_freeCCtx(encoder) == 0);
  CHECK(cpkt_zstd_ZSTD_freeDCtx(decoder) == 0);
  CHECK(allocations == 0);
  return 0;
}
