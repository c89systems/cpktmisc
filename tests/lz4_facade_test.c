#include <cpkt/lz4.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);          \
      return 1;                                                                \
    }                                                                          \
  } while (0)

int main(void) {
  const char input[] = "full LZ4 block, frame and file surfaces";
  char encoded[512], decoded[128];
  int length;
  size_t size, consumed;
  cpkt_lz4_LZ4_stream_t stream;
  cpkt_lz4_LZ4_streamHC_t hc;
  cpkt_lz4_LZ4F_preferences_t preferences = CPKT_LZ4_LZ4F_INIT_PREFERENCES;
  cpkt_lz4_LZ4F_frameInfo_t frame;
  cpkt_lz4_LZ4F_dctx *dctx;
  FILE *file;
  cpkt_lz4_LZ4_writeFile_t *writer;
  cpkt_lz4_LZ4_readFile_t *reader;
  CHECK(cpkt_lz4_LZ4_initStream(&stream, sizeof(stream)) == &stream);
  CHECK(cpkt_lz4_LZ4_initStreamHC(&hc, sizeof(hc)) == &hc);
  length = cpkt_lz4_LZ4_compress_fast_continue(
      &stream, input, encoded, sizeof(input), sizeof(encoded), 1);
  CHECK(length > 0);
  CHECK(cpkt_lz4_LZ4_decompress_safe(encoded, decoded, length,
                                     sizeof(decoded)) == (int)sizeof(input));
  CHECK(memcmp(input, decoded, sizeof(input)) == 0);
  length = cpkt_lz4_LZ4_compress_HC_continue(&hc, input, encoded, sizeof(input),
                                             sizeof(encoded));
  CHECK(length > 0);
  CHECK(cpkt_lz4_LZ4_decompress_safe(encoded, decoded, length,
                                     sizeof(decoded)) == (int)sizeof(input));
  CHECK(memcmp(input, decoded, sizeof(input)) == 0);

  preferences.frameInfo.contentSize = cpkt_lz4_u64_make(sizeof(input), 0);
  size = cpkt_lz4_LZ4F_compressFrame(encoded, sizeof(encoded), input,
                                     sizeof(input), &preferences);
  CHECK(!cpkt_lz4_LZ4F_isError(size));
  CHECK(!cpkt_lz4_LZ4F_isError(
      cpkt_lz4_LZ4F_createDecompressionContext(&dctx, CPKT_LZ4_LZ4F_VERSION)));
  consumed = size;
  CHECK(!cpkt_lz4_LZ4F_isError(
      cpkt_lz4_LZ4F_getFrameInfo(dctx, &frame, encoded, &consumed)));
  CHECK(frame.contentSize.lo == sizeof(input) && frame.contentSize.hi == 0);
  cpkt_lz4_LZ4F_freeDecompressionContext(dctx);

  file = tmpfile();
  CHECK(file != NULL);
  CHECK(!cpkt_lz4_LZ4F_isError(
      cpkt_lz4_LZ4F_writeOpen(&writer, file, &preferences)));
  CHECK(cpkt_lz4_LZ4F_write(writer, input, sizeof(input)) == sizeof(input));
  CHECK(!cpkt_lz4_LZ4F_isError(cpkt_lz4_LZ4F_writeClose(writer)));
  rewind(file);
  CHECK(!cpkt_lz4_LZ4F_isError(cpkt_lz4_LZ4F_readOpen(&reader, file)));
  CHECK(cpkt_lz4_LZ4F_read(reader, decoded, sizeof(decoded)) == sizeof(input));
  CHECK(memcmp(input, decoded, sizeof(input)) == 0);
  CHECK(!cpkt_lz4_LZ4F_isError(cpkt_lz4_LZ4F_readClose(reader)));
  CHECK(fclose(file) == 0);
  CHECK(cpkt_lz4_LZ4F_isError(
      cpkt_lz4_LZ4F_getBlockSize((cpkt_lz4_LZ4F_blockSizeID_t)999)));
  return 0;
}
