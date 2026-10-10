#include <cpkt/archive.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);          \
      return 1;                                                                \
    }                                                                          \
  } while (0)

struct input_state {
  const char *data;
  size_t length, position;
  int reads, skips, seeks;
};
static cpkt_archive_la_ssize_t read_block(struct archive *archive, void *data,
                                          const void **buffer) {
  struct input_state *input;
  size_t size;
  (void)archive;
  input = data;
  size = input->length - input->position;
  if (size > 37)
    size = 37;
  *buffer = input->data + input->position;
  input->position += size;
  ++input->reads;
  return (cpkt_archive_la_ssize_t)size;
}
static cpkt_compression_i64 skip_block(struct archive *archive, void *data,
                                       cpkt_compression_i64 request) {
  struct input_state *input;
  size_t size;
  (void)archive;
  input = data;
  size = request.lo;
  if (request.hi != 0 || size > input->length - input->position)
    size = input->length - input->position;
  input->position += size;
  ++input->skips;
  return cpkt_archive_i64_make((unsigned int)size, 0);
}
static cpkt_compression_i64 seek_block(struct archive *archive, void *data,
                                       cpkt_compression_i64 offset,
                                       int whence) {
  struct input_state *input;
  long delta, base, position;
  (void)archive;
  input = data;
  ++input->seeks;
  if (offset.hi == -1) {
    delta = -(long)(~offset.lo + 1U);
  } else if (offset.hi == 0)
    delta = (long)offset.lo;
  else
    return cpkt_archive_i64_make(4294967295U, -1);
  base = whence == SEEK_END   ? (long)input->length
         : whence == SEEK_CUR ? (long)input->position
                              : 0;
  position = base + delta;
  if (position < 0 || (size_t)position > input->length)
    return cpkt_archive_i64_make(4294967295U, -1);
  input->position = (size_t)position;
  return cpkt_archive_i64_make((unsigned int)position, 0);
}
static const char *lookup_name(void *data, cpkt_compression_i64 id) {
  cpkt_compression_i64 *received;
  received = data;
  *received = id;
  return "full-width-id";
}
static void lookup_cleanup(void *data) {
  ((cpkt_compression_i64 *)data)->hi = -99;
}

static int codec_round_trip(int filter, int zip) {
  struct archive *writer, *reader;
  struct archive_entry *entry;
  char encoded[65536], decoded[64];
  const char payload[] = "archive codec closure";
  size_t used;
  cpkt_compression_i64 size;
  struct input_state input;
  writer = cpkt_archive_archive_write_new();
  CHECK(writer != NULL);
  CHECK((zip ? cpkt_archive_archive_write_set_format_zip(writer)
             : cpkt_archive_archive_write_set_format_pax_restricted(writer)) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_add_filter(writer, filter) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_open_memory(writer, encoded, sizeof(encoded),
                                               &used) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  entry = cpkt_archive_archive_entry_new();
  CHECK(entry != NULL);
  cpkt_archive_archive_entry_set_pathname(entry, "entry.txt");
  cpkt_archive_archive_entry_set_filetype(entry, CPKT_ARCHIVE_AE_IFREG);
  cpkt_archive_archive_entry_set_perm(entry, 0644);
  cpkt_archive_archive_entry_set_size(
      entry, cpkt_archive_i64_make(sizeof(payload), 0));
  CHECK(cpkt_archive_archive_write_header(writer, entry) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_data(writer, payload, sizeof(payload)) ==
        (cpkt_archive_la_ssize_t)sizeof(payload));
  cpkt_archive_archive_entry_free(entry);
  CHECK(cpkt_archive_archive_write_close(writer) == CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_free(writer) == CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(used > 0 && used < sizeof(encoded));
  reader = cpkt_archive_archive_read_new();
  CHECK(reader != NULL);
  CHECK(cpkt_archive_archive_read_support_filter_all(reader) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK((zip ? cpkt_archive_archive_read_support_format_zip_seekable(reader)
             : cpkt_archive_archive_read_support_format_all(reader)) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  memset(&input, 0, sizeof(input));
  input.data = encoded;
  input.length = used;
  if (zip)
    CHECK(cpkt_archive_archive_read_set_seek_callback(reader, seek_block) ==
          CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_read_open2(reader, &input, NULL, read_block,
                                        skip_block,
                                        NULL) == CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_read_next_header(reader, &entry) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(strcmp(cpkt_archive_archive_entry_pathname(entry), "entry.txt") == 0);
  size = cpkt_archive_archive_entry_size(entry);
  CHECK(size.lo == sizeof(payload) && size.hi == 0);
  CHECK(cpkt_archive_archive_read_data(reader, decoded, sizeof(decoded)) ==
        (cpkt_archive_la_ssize_t)sizeof(payload));
  CHECK(memcmp(payload, decoded, sizeof(payload)) == 0);
  CHECK(cpkt_archive_archive_read_next_header(reader, &entry) ==
        CPKT_ARCHIVE_ARCHIVE_EOF);
  CHECK(input.reads > 1);
  if (zip)
    CHECK(input.seeks > 0);
  CHECK(cpkt_archive_archive_read_free(reader) == CPKT_ARCHIVE_ARCHIVE_OK);
  return 0;
}

int main(void) {
  const int filters[] = {
      CPKT_ARCHIVE_ARCHIVE_FILTER_NONE,  CPKT_ARCHIVE_ARCHIVE_FILTER_GZIP,
      CPKT_ARCHIVE_ARCHIVE_FILTER_BZIP2, CPKT_ARCHIVE_ARCHIVE_FILTER_XZ,
      CPKT_ARCHIVE_ARCHIVE_FILTER_LZMA,  CPKT_ARCHIVE_ARCHIVE_FILTER_LZIP,
      CPKT_ARCHIVE_ARCHIVE_FILTER_LZ4,   CPKT_ARCHIVE_ARCHIVE_FILTER_ZSTD,
      CPKT_ARCHIVE_ARCHIVE_FILTER_LZOP};
  size_t i;
  struct archive_entry *entry, *copy;
  struct archive *disk;
  cpkt_compression_i64 value, received;
  cpkt_archive_stat stat;
  for (i = 0; i < sizeof(filters) / sizeof(filters[0]); ++i)
    CHECK(codec_round_trip(filters[i], 0) == 0);
  CHECK(codec_round_trip(CPKT_ARCHIVE_ARCHIVE_FILTER_NONE, 1) == 0);
  entry = cpkt_archive_archive_entry_new();
  copy = cpkt_archive_archive_entry_new();
  CHECK(entry && copy);
  cpkt_archive_archive_entry_set_size(entry, cpkt_archive_i64_make(123, 5));
  cpkt_archive_archive_entry_set_uid(entry, cpkt_archive_i64_make(456, 7));
  cpkt_archive_archive_entry_set_mtime(
      entry, cpkt_archive_i64_make(4294967294U, -1), 123);
  CHECK(cpkt_archive_archive_entry_stat(entry, &stat) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(stat.st_size.lo == 123 && stat.st_size.hi == 5);
  cpkt_archive_archive_entry_copy_stat(copy, &stat);
  value = cpkt_archive_archive_entry_size(copy);
  CHECK(value.lo == 123 && value.hi == 5);
  value = cpkt_archive_archive_entry_mtime(copy);
  CHECK(value.lo == 4294967294U && value.hi == -1);
  cpkt_archive_archive_entry_free(entry);
  cpkt_archive_archive_entry_free(copy);
  disk = cpkt_archive_archive_read_disk_new();
  CHECK(disk != NULL);
  received = cpkt_archive_i64_make(0, 0);
  CHECK(cpkt_archive_archive_read_disk_set_gname_lookup(
            disk, &received, lookup_name, lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(strcmp(cpkt_archive_archive_read_disk_gname(
                   disk, cpkt_archive_i64_make(12, 34)),
               "full-width-id") == 0);
  CHECK(received.lo == 12 && received.hi == 34);
  cpkt_archive_archive_set_error(disk, 123, "error %s %d", "format", 7);
  CHECK(cpkt_archive_archive_errno(disk) == 123);
  CHECK(strcmp(cpkt_archive_archive_error_string(disk), "error format 7") == 0);
  CHECK(cpkt_archive_archive_free(disk) == CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(received.hi == -99);
  return 0;
}
