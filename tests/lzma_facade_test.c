#include <cpkt/lzma.h>
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

static void *fail_allocate(void *opaque, size_t count, size_t size) {
  (void)count;
  (void)size;
  ++*(int *)opaque;
  return NULL;
}

static int copy_failure_contract(void) {
  cpkt_lzma_lzma_filter source[5], destination[5], saved[5];
  cpkt_lzma_lzma_options_lzma options;
  cpkt_lzma_lzma_allocator allocator;
  int calls, error_position;
  memset(source, 0, sizeof(source));
  memset(destination, 0, sizeof(destination));
  memset(&options, 0, sizeof(options));
  CHECK(!cpkt_lzma_lzma_lzma_preset(&options, 1));
  destination[0].id = CPKT_LZMA_LZMA_FILTER_LZMA2;
  destination[0].options = &options;
  destination[1].id = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  memcpy(saved, destination, sizeof(saved));
  source[0].id = cpkt_lzma_u64_make(12345, 0);
  source[0].options = &options;
  source[1].id = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  CHECK(cpkt_lzma_lzma_filters_copy(source, destination, NULL) ==
        CPKT_LZMA_LZMA_OPTIONS_ERROR);
  CHECK(memcmp(destination, saved, sizeof(saved)) == 0);
  source[0].id = CPKT_LZMA_LZMA_FILTER_LZMA2;
  calls = 0;
  allocator.alloc = fail_allocate;
  allocator.free = NULL;
  allocator.opaque = &calls;
  CHECK(cpkt_lzma_lzma_filters_copy(source, destination, &allocator) ==
        CPKT_LZMA_LZMA_MEM_ERROR);
  CHECK(calls == 1 && memcmp(destination, saved, sizeof(saved)) == 0);
  CHECK(cpkt_lzma_lzma_filters_copy(NULL, destination, NULL) ==
        CPKT_LZMA_LZMA_PROG_ERROR);
  CHECK(memcmp(destination, saved, sizeof(saved)) == 0);
  CHECK(cpkt_lzma_lzma_str_to_filters("unknown-filter", &error_position,
                                      destination, 0, NULL) != NULL);
  CHECK(memcmp(destination, saved, sizeof(saved)) == 0);
  calls = 0;
  CHECK(cpkt_lzma_lzma_str_to_filters("1", &error_position, destination, 0,
                                      &allocator) != NULL);
  CHECK(calls == 1 && memcmp(destination, saved, sizeof(saved)) == 0);
  CHECK(cpkt_lzma_lzma_str_to_filters("1", &error_position, destination, 0,
                                      NULL) == NULL);
  CHECK(destination[0].id.lo == CPKT_LZMA_LZMA_FILTER_LZMA2.lo &&
        destination[0].id.hi == CPKT_LZMA_LZMA_FILTER_LZMA2.hi &&
        destination[0].options != NULL);
  cpkt_lzma_lzma_filters_free(destination, NULL);
  return 0;
}

static int reinitialize_stream_contract(void) {
  const unsigned char input[] = "reuse a block stream as a regular stream";
  unsigned char output[512];
  cpkt_lzma_lzma_stream stream = CPKT_LZMA_LZMA_STREAM_INIT;
  cpkt_lzma_lzma_options_lzma options;
  cpkt_lzma_lzma_filter filters[5];
  cpkt_lzma_lzma_block *block;
  memset(&options, 0, sizeof(options));
  memset(filters, 0, sizeof(filters));
  CHECK(!cpkt_lzma_lzma_lzma_preset(&options, 1));
  filters[0].id = CPKT_LZMA_LZMA_FILTER_LZMA2;
  filters[0].options = &options;
  filters[1].id = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  block = malloc(sizeof(*block));
  CHECK(block != NULL);
  memset(block, 0, sizeof(*block));
  block->check = CPKT_LZMA_LZMA_CHECK_CRC64;
  block->compressed_size = block->uncompressed_size =
      CPKT_LZMA_LZMA_VLI_UNKNOWN;
  block->filters = filters;
  CHECK(cpkt_lzma_lzma_block_encoder(&stream, block) == CPKT_LZMA_LZMA_OK);
  CHECK(
      cpkt_lzma_lzma_easy_encoder(&stream, 12345, CPKT_LZMA_LZMA_CHECK_CRC64) ==
      CPKT_LZMA_LZMA_OPTIONS_ERROR);
  stream.next_in = input;
  stream.avail_in = sizeof(input);
  stream.next_out = output;
  stream.avail_out = sizeof(output);
  CHECK(cpkt_lzma_lzma_code(&stream, CPKT_LZMA_LZMA_FINISH) ==
        CPKT_LZMA_LZMA_STREAM_END);
  CHECK(cpkt_lzma_lzma_easy_encoder(&stream, 1, CPKT_LZMA_LZMA_CHECK_CRC64) ==
        CPKT_LZMA_LZMA_OK);
  free(block);
  stream.next_in = input;
  stream.avail_in = sizeof(input);
  stream.next_out = output;
  stream.avail_out = sizeof(output);
  CHECK(cpkt_lzma_lzma_code(&stream, CPKT_LZMA_LZMA_FINISH) ==
        CPKT_LZMA_LZMA_STREAM_END);
  block = malloc(sizeof(*block));
  CHECK(block != NULL);
  memset(block, 0, sizeof(*block));
  block->version = 12345;
  block->filters = filters;
  CHECK(cpkt_lzma_lzma_block_encoder(&stream, block) ==
        CPKT_LZMA_LZMA_OPTIONS_ERROR);
  free(block);
  cpkt_lzma_lzma_end(&stream);
  return 0;
}

static int fresh_output_contract(void) {
  unsigned char header[1024], bytes[16];
  cpkt_lzma_lzma_options_lzma options;
  cpkt_lzma_lzma_filter filters[5], decoded_filters[5];
  cpkt_lzma_lzma_filter properties_filter;
  cpkt_lzma_lzma_block block, decoded;
  cpkt_compression_u64 single, incremental;
  cpkt_lzma_lzma_ret status;
  size_t size, position, vli_position;
  memset(&options, 0, sizeof(options));
  memset(filters, 0, sizeof(filters));
  memset(&block, 0, sizeof(block));
  memset(&decoded, 0, sizeof(decoded));
  CHECK(!cpkt_lzma_lzma_lzma_preset(&options, 1));
  filters[0].id = CPKT_LZMA_LZMA_FILTER_LZMA2;
  filters[0].options = &options;
  filters[1].id = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  block.check = CPKT_LZMA_LZMA_CHECK_CRC64;
  block.compressed_size = block.uncompressed_size = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  block.filters = filters;
  CHECK(cpkt_lzma_lzma_block_header_size(&block) == CPKT_LZMA_LZMA_OK);
  CHECK(block.header_size <= sizeof(header));
  CHECK(cpkt_lzma_lzma_block_header_encode(&block, header) ==
        CPKT_LZMA_LZMA_OK);
  decoded.check = block.check;
  decoded.header_size = block.header_size;
  decoded.filters = decoded_filters;
  /* The upstream output contract does not require initialized filters. */
  CHECK(cpkt_lzma_lzma_block_header_decode(&decoded, NULL, header) ==
        CPKT_LZMA_LZMA_OK);
  CHECK(decoded.filters == decoded_filters);
  CHECK(decoded_filters[0].id.lo == filters[0].id.lo &&
        decoded_filters[0].id.hi == filters[0].id.hi);
  CHECK(decoded_filters[0].options != NULL);
  cpkt_lzma_lzma_filters_free(decoded_filters, NULL);
  CHECK(cpkt_lzma_lzma_properties_encode(&filters[0], bytes) ==
        CPKT_LZMA_LZMA_OK);
  /* Only the ID is input; the options pointer is output-only. */
  properties_filter.id = filters[0].id;
  CHECK(cpkt_lzma_lzma_properties_decode(&properties_filter, NULL, bytes, 1) ==
        CPKT_LZMA_LZMA_OK);
  CHECK(properties_filter.options != NULL);
  decoded_filters[0] = properties_filter;
  decoded_filters[1].id = CPKT_LZMA_LZMA_VLI_UNKNOWN;
  cpkt_lzma_lzma_filters_free(decoded_filters, NULL);

  size = 0;
  CHECK(cpkt_lzma_lzma_vli_encode(cpkt_lzma_u64_make(123, 77), NULL, bytes,
                                  &size, sizeof(bytes)) == CPKT_LZMA_LZMA_OK);
  position = 0;
  CHECK(cpkt_lzma_lzma_vli_decode(&single, NULL, bytes, &position, size) ==
        CPKT_LZMA_LZMA_OK);
  CHECK(single.lo == 123 && single.hi == 77);
  position = vli_position = 0;
  do {
    status = cpkt_lzma_lzma_vli_decode(&incremental, &vli_position, bytes,
                                       &position, position + 1);
    CHECK(status == CPKT_LZMA_LZMA_OK || status == CPKT_LZMA_LZMA_STREAM_END);
    CHECK(position <= size);
  } while (status != CPKT_LZMA_LZMA_STREAM_END && position < size);
  CHECK(status == CPKT_LZMA_LZMA_STREAM_END && position == size);
  CHECK(incremental.lo == 123 && incremental.hi == 77);
  return 0;
}

int main(void) {
  const unsigned char input[] =
      "full liblzma streams, blocks, filters and indexes";
  unsigned char encoded[512], decoded[128], vli_bytes[16], index_bytes[128];
  cpkt_lzma_lzma_stream encoder = CPKT_LZMA_LZMA_STREAM_INIT;
  cpkt_lzma_lzma_stream decoder = CPKT_LZMA_LZMA_STREAM_INIT;
  cpkt_lzma_lzma_ret status;
  size_t size, consumed, position, vli_position, index_size;
  cpkt_compression_u64 word, progress_in, progress_out;
  cpkt_lzma_lzma_filter filters[5], copied[5];
  cpkt_lzma_lzma_options_lzma options;
  cpkt_lzma_lzma_index *index, *decoded_index;
  cpkt_lzma_lzma_index_iter iter, saved_iter;
  cpkt_lzma_lzma_stream_flags flags;
  cpkt_lzma_lzma_block block;
  CHECK(cpkt_lzma_lzma_code(NULL, CPKT_LZMA_LZMA_RUN) ==
        CPKT_LZMA_LZMA_PROG_ERROR);
  CHECK(cpkt_lzma_lzma_easy_encoder(NULL, 1, CPKT_LZMA_LZMA_CHECK_CRC64) ==
        CPKT_LZMA_LZMA_PROG_ERROR);
  CHECK(cpkt_lzma_lzma_stream_decoder(NULL, CPKT_LZMA_LZMA_VLI_MAX, 0) ==
        CPKT_LZMA_LZMA_PROG_ERROR);
  CHECK(cpkt_lzma_lzma_memlimit_set(NULL, CPKT_LZMA_LZMA_VLI_MAX) ==
        CPKT_LZMA_LZMA_PROG_ERROR);
  CHECK(copy_failure_contract() == 0);
  CHECK(reinitialize_stream_contract() == 0);
  CHECK(fresh_output_contract() == 0);
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

  word = cpkt_lzma_u64_make(0, 0);
  position = consumed = 0;
  CHECK(cpkt_lzma_lzma_stream_buffer_decode(
            &word, 0, NULL, encoded, &position, size, decoded, &consumed,
            sizeof(decoded)) == CPKT_LZMA_LZMA_MEMLIMIT_ERROR);
  CHECK(word.lo != 0 || word.hi != 0);
  CHECK(position == 0 && consumed == 0);
  CHECK(cpkt_lzma_lzma_stream_buffer_decode(
            &word, 0, NULL, encoded, &position, size, decoded, &consumed,
            sizeof(decoded)) == CPKT_LZMA_LZMA_OK);
  CHECK(consumed == sizeof(input) && memcmp(input, decoded, consumed) == 0);

  position = 0;
  word = cpkt_lzma_u64_make(123, 456);
  CHECK(cpkt_lzma_lzma_vli_encode(word, NULL, vli_bytes, &position,
                                  sizeof(vli_bytes)) == CPKT_LZMA_LZMA_OK);
  size = position;
  position = 0;
  word = cpkt_lzma_u64_make(0, 0);
  CHECK(cpkt_lzma_lzma_vli_decode(&word, NULL, vli_bytes, &position, size) ==
        CPKT_LZMA_LZMA_OK);
  CHECK(word.lo == 123 && word.hi == 456);
  position = vli_position = 0;
  word = cpkt_lzma_u64_make(0, 0);
  do {
    status = cpkt_lzma_lzma_vli_decode(&word, &vli_position, vli_bytes,
                                       &position, position + 1);
    CHECK(status == CPKT_LZMA_LZMA_OK || status == CPKT_LZMA_LZMA_STREAM_END);
    CHECK(position <= size);
  } while (status != CPKT_LZMA_LZMA_STREAM_END && position < size);
  CHECK(status == CPKT_LZMA_LZMA_STREAM_END && position == size);
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
  memcpy(&saved_iter, &iter, sizeof(iter));
  CHECK(cpkt_lzma_lzma_index_iter_next(&iter, CPKT_LZMA_LZMA_INDEX_ITER_BLOCK));
  CHECK(memcmp(&iter, &saved_iter, sizeof(iter)) == 0);
  CHECK(cpkt_lzma_lzma_index_iter_locate(&iter, cpkt_lzma_u64_make(322, 17)));
  CHECK(memcmp(&iter, &saved_iter, sizeof(iter)) == 0);
  CHECK(!cpkt_lzma_lzma_index_iter_locate(&iter, cpkt_lzma_u64_make(0, 0)));
  CHECK(iter.stream.flags_present &&
        iter.stream.flags.check == CPKT_LZMA_LZMA_CHECK_CRC64);
  index_size = 0;
  CHECK(cpkt_lzma_lzma_index_buffer_encode(index, index_bytes, &index_size,
                                           sizeof(index_bytes)) ==
        CPKT_LZMA_LZMA_OK);
  decoded_index = NULL;
  word = cpkt_lzma_u64_make(0, 0);
  position = 0;
  CHECK(cpkt_lzma_lzma_index_buffer_decode(
            &decoded_index, &word, NULL, index_bytes, &position, index_size) ==
        CPKT_LZMA_LZMA_MEMLIMIT_ERROR);
  CHECK(decoded_index == NULL && position == 0);
  CHECK(word.lo != 0 || word.hi != 0);
  CHECK(cpkt_lzma_lzma_index_buffer_decode(&decoded_index, &word, NULL,
                                           index_bytes, &position,
                                           index_size) == CPKT_LZMA_LZMA_OK);
  CHECK(decoded_index != NULL && position == index_size);
  cpkt_lzma_lzma_index_iter_init(&iter, decoded_index);
  CHECK(
      !cpkt_lzma_lzma_index_iter_next(&iter, CPKT_LZMA_LZMA_INDEX_ITER_BLOCK));
  CHECK(iter.block.uncompressed_size.lo == 321 &&
        iter.block.uncompressed_size.hi == 17);
  cpkt_lzma_lzma_index_end(decoded_index, NULL);
  cpkt_lzma_lzma_index_end(index, NULL);
  word = cpkt_lzma_lzma_crc64((const unsigned char *)"123456789", 9,
                              cpkt_lzma_u64_make(0, 0));
  CHECK(word.lo == 0xdf1939faU && word.hi == 0x995dc9bbU);
  return 0;
}
