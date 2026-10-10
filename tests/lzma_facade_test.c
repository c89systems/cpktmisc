#include <cpkt/lzma.h>
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
  const unsigned char input[] =
      "full liblzma streams, blocks, filters and indexes";
  unsigned char encoded[512], decoded[128], vli_bytes[16];
  cpkt_lzma_lzma_stream encoder = CPKT_LZMA_LZMA_STREAM_INIT;
  cpkt_lzma_lzma_stream decoder = CPKT_LZMA_LZMA_STREAM_INIT;
  cpkt_lzma_lzma_ret status;
  size_t size, consumed, position;
  cpkt_compression_u64 word, progress_in, progress_out;
  cpkt_lzma_lzma_filter filters[5], copied[5];
  cpkt_lzma_lzma_options_lzma options;
  cpkt_lzma_lzma_index *index;
  cpkt_lzma_lzma_index_iter iter;
  cpkt_lzma_lzma_stream_flags flags;
  cpkt_lzma_lzma_block block;
  CHECK(cpkt_lzma_lzma_easy_encoder(&encoder, 1, CPKT_LZMA_LZMA_CHECK_CRC64) ==
        CPKT_LZMA_LZMA_OK);
  encoder.next_in = input;
  encoder.avail_in = sizeof(input);
  size = 0;
  do {
    encoder.next_out = encoded + size;
    encoder.avail_out = 1;
    status = cpkt_lzma_lzma_code(&encoder, CPKT_LZMA_LZMA_FINISH);
    CHECK(status == CPKT_LZMA_LZMA_OK || status == CPKT_LZMA_LZMA_STREAM_END);
    size += 1 - encoder.avail_out;
    CHECK(size < sizeof(encoded));
  } while (status != CPKT_LZMA_LZMA_STREAM_END);
  CHECK(encoder.total_in.lo == sizeof(input) && encoder.total_in.hi == 0);
  CHECK(encoder.total_out.lo == size && encoder.total_out.hi == 0);
  cpkt_lzma_lzma_get_progress(&encoder, &progress_in, &progress_out);
  CHECK(progress_in.lo == sizeof(input) && progress_in.hi == 0);
  CHECK(progress_out.lo == size && progress_out.hi == 0);
  CHECK(encoder.cpkt_state != NULL);
  cpkt_lzma_lzma_end(&encoder);
  CHECK(encoder.internal == NULL && encoder.cpkt_state == NULL);
  CHECK(cpkt_lzma_lzma_stream_decoder(&decoder, CPKT_LZMA_LZMA_VLI_MAX, 0) ==
        CPKT_LZMA_LZMA_OK);
  decoder.next_in = encoded;
  decoder.avail_in = size;
  consumed = 0;
  do {
    decoder.next_out = decoded + consumed;
    decoder.avail_out = 1;
    status = cpkt_lzma_lzma_code(&decoder, CPKT_LZMA_LZMA_FINISH);
    CHECK(status == CPKT_LZMA_LZMA_OK || status == CPKT_LZMA_LZMA_STREAM_END);
    consumed += 1 - decoder.avail_out;
    CHECK(consumed < sizeof(decoded));
  } while (status != CPKT_LZMA_LZMA_STREAM_END);
  CHECK(consumed == sizeof(input) && memcmp(input, decoded, consumed) == 0);
  cpkt_lzma_lzma_end(&decoder);

  position = 0;
  word = cpkt_lzma_u64_make(123, 456);
  CHECK(cpkt_lzma_lzma_vli_encode(word, NULL, vli_bytes, &position,
                                  sizeof(vli_bytes)) == CPKT_LZMA_LZMA_OK);
  size = position;
  position = 0;
  CHECK(cpkt_lzma_lzma_vli_decode(&word, NULL, vli_bytes, &position, size) ==
        CPKT_LZMA_LZMA_OK);
  CHECK(word.lo == 123 && word.hi == 456);
  CHECK(CPKT_LZMA_lzma_vli_is_valid(word));
  CHECK(!CPKT_LZMA_lzma_vli_is_valid(cpkt_lzma_u64_make(0, 2147483648U)));

  memset(&options, 0, sizeof(options));
  CHECK(!cpkt_lzma_lzma_lzma_preset(&options, 1));
  filters[0].id = CPKT_LZMA_LZMA_FILTER_LZMA2;
  filters[0].options = &options;
  filters[1].id = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  filters[1].options = NULL;
  CHECK(cpkt_lzma_lzma_filters_copy(filters, copied, NULL) ==
        CPKT_LZMA_LZMA_OK);
  CHECK(copied[0].id.lo == filters[0].id.lo &&
        copied[0].id.hi == filters[0].id.hi);
  CHECK(copied[0].options != filters[0].options);
  cpkt_lzma_lzma_filters_free(copied, NULL);
  memset(&block, 0, sizeof(block));
  block.version = 0;
  block.check = CPKT_LZMA_LZMA_CHECK_CRC64;
  block.compressed_size = block.uncompressed_size = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  block.filters = filters;
  CHECK(cpkt_lzma_lzma_block_encoder(&encoder, &block) == CPKT_LZMA_LZMA_OK);
  encoder.next_in = input;
  encoder.avail_in = sizeof(input);
  encoder.next_out = encoded;
  encoder.avail_out = sizeof(encoded);
  CHECK(cpkt_lzma_lzma_code(&encoder, CPKT_LZMA_LZMA_FINISH) ==
        CPKT_LZMA_LZMA_STREAM_END);
  CHECK(block.uncompressed_size.lo == sizeof(input) &&
        block.uncompressed_size.hi == 0);
  CHECK(block.filters == filters);
  cpkt_lzma_lzma_end(&encoder);

  index = cpkt_lzma_lzma_index_init(NULL);
  CHECK(index != NULL);
  CHECK(cpkt_lzma_lzma_index_append(index, NULL, cpkt_lzma_u64_make(100, 0),
                                    cpkt_lzma_u64_make(321, 17)) ==
        CPKT_LZMA_LZMA_OK);
  memset(&flags, 0, sizeof(flags));
  flags.check = CPKT_LZMA_LZMA_CHECK_CRC64;
  flags.backward_size = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  CHECK(cpkt_lzma_lzma_index_stream_flags(index, &flags) == CPKT_LZMA_LZMA_OK);
  cpkt_lzma_lzma_index_iter_init(&iter, index);
  CHECK(
      !cpkt_lzma_lzma_index_iter_next(&iter, CPKT_LZMA_LZMA_INDEX_ITER_BLOCK));
  CHECK(iter.block.uncompressed_size.lo == 321 &&
        iter.block.uncompressed_size.hi == 17);
  CHECK(iter.stream.flags_present &&
        iter.stream.flags.check == CPKT_LZMA_LZMA_CHECK_CRC64);
  CHECK(cpkt_lzma_lzma_index_iter_next(&iter, CPKT_LZMA_LZMA_INDEX_ITER_BLOCK));
  cpkt_lzma_lzma_index_end(index, NULL);
  word = cpkt_lzma_lzma_crc64((const unsigned char *)"123456789", 9,
                              cpkt_lzma_u64_make(0, 0));
  CHECK(word.lo == 0xdf1939faU && word.hi == 0x995dc9bbU);
  return 0;
}
