#include <bzlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <yaml.h>

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);          \
      return 1;                                                                \
    }                                                                          \
  } while (0)

struct input {
  const unsigned char *data;
  size_t size, position;
  int calls;
};
struct output {
  unsigned char data[1024];
  size_t size;
  int calls;
};
static int yaml_read(void *data, unsigned char *buffer, size_t capacity,
                     size_t *read) {
  struct input *input;
  size_t size;
  input = data;
  size = input->size - input->position;
  if (size > 7)
    size = 7;
  if (size > capacity)
    size = capacity;
  memcpy(buffer, input->data + input->position, size);
  input->position += size;
  ++input->calls;
  *read = size;
  return 1;
}
static int yaml_write(void *data, unsigned char *buffer, size_t size) {
  struct output *output;
  output = data;
  if (size > sizeof(output->data) - output->size)
    return 0;
  memcpy(output->data + output->size, buffer, size);
  output->size += size;
  ++output->calls;
  return 1;
}
static void *bz_allocate(void *data, int items, int size) {
  void *memory;
  memory = malloc((size_t)items * (size_t)size);
  if (memory)
    ++*(int *)data;
  return memory;
}
static void bz_release(void *data, void *memory) {
  if (memory) {
    --*(int *)data;
    free(memory);
  }
}
static int test_yaml(void) {
  const unsigned char text[] = "name: archive\nvalues: [1, 2, 3]\n";
  yaml_parser_t parser;
  yaml_emitter_t emitter;
  yaml_event_t event;
  yaml_token_t token;
  yaml_document_t document;
  yaml_node_t *root;
  struct input input;
  struct output output;
  int done, scalars;
  CHECK(strcmp(yaml_get_version_string(), "0.2.5") == 0);
  input.data = text;
  input.size = sizeof(text) - 1;
  input.position = 0;
  input.calls = 0;
  CHECK(yaml_parser_initialize(&parser));
  yaml_parser_set_input(&parser, yaml_read, &input);
  done = scalars = 0;
  while (!done) {
    CHECK(yaml_parser_parse(&parser, &event));
    if (event.type == YAML_SCALAR_EVENT)
      ++scalars;
    done = event.type == YAML_STREAM_END_EVENT;
    yaml_event_delete(&event);
  }
  CHECK(scalars == 6 && input.calls > 1);
  yaml_parser_delete(&parser);
  CHECK(yaml_parser_initialize(&parser));
  yaml_parser_set_input_string(&parser, text, sizeof(text) - 1);
  CHECK(yaml_parser_load(&parser, &document));
  root = yaml_document_get_root_node(&document);
  CHECK(root && root->type == YAML_MAPPING_NODE);
  CHECK(root->data.mapping.pairs.top - root->data.mapping.pairs.start == 2);
  memset(&output, 0, sizeof(output));
  CHECK(yaml_emitter_initialize(&emitter));
  yaml_emitter_set_output(&emitter, yaml_write, &output);
  CHECK(yaml_emitter_open(&emitter));
  CHECK(yaml_emitter_dump(&emitter, &document));
  CHECK(yaml_emitter_close(&emitter));
  yaml_emitter_delete(&emitter);
  yaml_parser_delete(&parser);
  CHECK(output.size > 0 && output.calls > 0);
  CHECK(yaml_parser_initialize(&parser));
  yaml_parser_set_input_string(&parser, output.data, output.size);
  CHECK(yaml_parser_load(&parser, &document));
  root = yaml_document_get_root_node(&document);
  CHECK(root && root->type == YAML_MAPPING_NODE);
  yaml_document_delete(&document);
  yaml_parser_delete(&parser);
  CHECK(yaml_parser_initialize(&parser));
  yaml_parser_set_input_string(&parser, text, sizeof(text) - 1);
  done = 0;
  while (!done) {
    CHECK(yaml_parser_scan(&parser, &token));
    done = token.type == YAML_STREAM_END_TOKEN;
    yaml_token_delete(&token);
  }
  yaml_parser_delete(&parser);
  CHECK(yaml_parser_initialize(&parser));
  yaml_parser_set_input_string(&parser, (const unsigned char *)"[unterminated",
                               13);
  do {
    done = !yaml_parser_parse(&parser, &event);
    if (!done)
      yaml_event_delete(&event);
  } while (!done);
  CHECK(parser.problem != NULL);
  yaml_parser_delete(&parser);
  return 0;
}
static int test_bzip2(void) {
  const char text[] = "C89 bzip2 incremental compression";
  char encoded[512], decoded[128];
  bz_stream stream;
  int status, allocations;
  size_t size, length;
  CHECK(strncmp(BZ2_bzlibVersion(), "1.0.8", 5) == 0);
  allocations = 0;
  memset(&stream, 0, sizeof(stream));
  stream.bzalloc = bz_allocate;
  stream.bzfree = bz_release;
  stream.opaque = &allocations;
  CHECK(BZ2_bzCompressInit(&stream, 1, 0, 0) == BZ_OK);
  stream.next_in = (char *)text;
  stream.avail_in = sizeof(text);
  size = 0;
  do {
    stream.next_out = encoded + size;
    stream.avail_out = 1;
    status = BZ2_bzCompress(&stream, BZ_FINISH);
    CHECK(status == BZ_FINISH_OK || status == BZ_STREAM_END);
    size += 1 - stream.avail_out;
    CHECK(size < sizeof(encoded));
  } while (status != BZ_STREAM_END);
  CHECK(stream.total_in_lo32 == sizeof(text) && stream.total_in_hi32 == 0);
  CHECK(BZ2_bzCompressEnd(&stream) == BZ_OK && allocations == 0);
  memset(&stream, 0, sizeof(stream));
  CHECK(BZ2_bzDecompressInit(&stream, 0, 0) == BZ_OK);
  stream.next_in = encoded;
  stream.avail_in = (unsigned int)size;
  length = 0;
  do {
    stream.next_out = decoded + length;
    stream.avail_out = 1;
    status = BZ2_bzDecompress(&stream);
    CHECK(status == BZ_OK || status == BZ_STREAM_END);
    length += 1 - stream.avail_out;
    CHECK(length < sizeof(decoded));
  } while (status != BZ_STREAM_END);
  CHECK(length == sizeof(text) && memcmp(text, decoded, length) == 0);
  CHECK(BZ2_bzDecompressEnd(&stream) == BZ_OK);
  memset(&stream, 0, sizeof(stream));
  CHECK(BZ2_bzDecompressInit(&stream, 0, 0) == BZ_OK);
  stream.next_in = (char *)"bad";
  stream.avail_in = 3;
  stream.next_out = decoded;
  stream.avail_out = sizeof(decoded);
  CHECK(BZ2_bzDecompress(&stream) == BZ_DATA_ERROR_MAGIC);
  CHECK(BZ2_bzDecompressEnd(&stream) == BZ_OK);
  return 0;
}
int main(void) {
  CHECK(test_yaml() == 0);
  CHECK(test_bzip2() == 0);
  return 0;
}
