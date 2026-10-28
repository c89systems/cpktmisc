#include <cpkt/archive.h>
#include <pthread.h>
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

static int null_lookup_calls, null_cleanup_calls;
static const char *null_lookup_name(void *data, cpkt_compression_i64 id) {
  (void)id;
  if (data == NULL)
    ++null_lookup_calls;
  return "without-client-data";
}
static cpkt_compression_i64 null_lookup_id(void *data, const char *name,
                                           cpkt_compression_i64 id) {
  (void)name;
  if (data == NULL)
    ++null_lookup_calls;
  return id;
}
static void null_lookup_cleanup(void *data) {
  (void)data;
  ++null_cleanup_calls;
}

static int null_lookup_contract(void) {
  struct archive *reader, *writer;
  cpkt_compression_i64 id, result;
  reader = cpkt_archive_archive_read_disk_new();
  writer = cpkt_archive_archive_write_disk_new();
  CHECK(reader != NULL && writer != NULL);
  id = cpkt_archive_i64_make(123, 17);
  CHECK(cpkt_archive_archive_read_disk_set_gname_lookup(
            reader, NULL, null_lookup_name, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_read_disk_set_uname_lookup(
            reader, NULL, null_lookup_name, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_disk_set_group_lookup(
            writer, NULL, null_lookup_id, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_disk_set_user_lookup(
            writer, NULL, null_lookup_id, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(strcmp(cpkt_archive_archive_read_disk_gname(reader, id),
               "without-client-data") == 0);
  CHECK(strcmp(cpkt_archive_archive_read_disk_uname(reader, id),
               "without-client-data") == 0);
  result = cpkt_archive_archive_write_disk_gid(writer, "group", id);
  CHECK(result.lo == id.lo && result.hi == id.hi);
  result = cpkt_archive_archive_write_disk_uid(writer, "user", id);
  CHECK(result.lo == id.lo && result.hi == id.hi && null_lookup_calls == 4);
  /* Upstream skips cleanup when the original client data is NULL. */
  CHECK(cpkt_archive_archive_read_disk_set_gname_lookup(
            reader, NULL, null_lookup_name, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_read_disk_set_uname_lookup(
            reader, NULL, null_lookup_name, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_disk_set_group_lookup(
            writer, NULL, null_lookup_id, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_disk_set_user_lookup(
            writer, NULL, null_lookup_id, null_lookup_cleanup) ==
        CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(null_cleanup_calls == 0);
  CHECK(cpkt_archive_archive_read_free(reader) == CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(cpkt_archive_archive_write_free(writer) == CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(null_cleanup_calls == 0);
  return 0;
}

static int codec_round_trip(int filter, int zip, char *encoded,
                            size_t capacity) {
  struct archive *writer, *reader;
  struct archive_entry *entry;
  char decoded[64];
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
  CHECK(cpkt_archive_archive_write_open_memory(
            writer, encoded, capacity, &used) == CPKT_ARCHIVE_ARCHIVE_OK);
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
  CHECK(used > 0 && used < capacity);
  if (filter == CPKT_ARCHIVE_ARCHIVE_FILTER_GZIP) {
    CHECK(used > 2);
    CHECK((unsigned char)encoded[0] == 0x1f);
    CHECK((unsigned char)encoded[1] == 0x8b);
  }
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
  CHECK(cpkt_archive_archive_filter_code(reader, 0) == filter);
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

static void *codec_worker(void *argument) {
  const int filters[] = {
      CPKT_ARCHIVE_ARCHIVE_FILTER_NONE,  CPKT_ARCHIVE_ARCHIVE_FILTER_GZIP,
      CPKT_ARCHIVE_ARCHIVE_FILTER_BZIP2, CPKT_ARCHIVE_ARCHIVE_FILTER_XZ,
      CPKT_ARCHIVE_ARCHIVE_FILTER_LZMA,  CPKT_ARCHIVE_ARCHIVE_FILTER_LZIP,
      CPKT_ARCHIVE_ARCHIVE_FILTER_LZ4,   CPKT_ARCHIVE_ARCHIVE_FILTER_ZSTD};
  size_t i;
  char *encoded;
  int *status;
  status = argument;
  *status = 1;
  encoded = malloc(65536);
  if (encoded == NULL) {
    fputs("archive codec buffer allocation failed\n", stderr);
    return NULL;
  }
  for (i = 0; i < sizeof(filters) / sizeof(filters[0]); ++i) {
    if (codec_round_trip(filters[i], 0, encoded, 65536) != 0) {
      free(encoded);
      return NULL;
    }
  }
  *status =
      codec_round_trip(CPKT_ARCHIVE_ARCHIVE_FILTER_NONE, 1, encoded, 65536);
  free(encoded);
  return NULL;
}

int main(void) {
  pthread_t thread;
  int codec_status;
  struct archive_entry *entry, *copy;
  struct archive *disk;
  cpkt_compression_i64 value, received;
  cpkt_archive_stat stat;
  CHECK(cpkt_archive_archive_liblzo2_version() == NULL);
  CHECK(cpkt_archive_archive_zlib_version() != NULL);
  CHECK(null_lookup_contract() == 0);
  /* Default thread attributes retain each platform's normal stack budget. */
  CHECK(pthread_create(&thread, NULL, codec_worker, &codec_status) == 0);
  CHECK(pthread_join(thread, NULL) == 0);
  CHECK(codec_status == 0);
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
  cpkt_archive_archive_set_error(disk, 456, NULL);
  CHECK(cpkt_archive_archive_errno(disk) == 456);
  CHECK(cpkt_archive_archive_error_string(disk) == NULL);
  CHECK(cpkt_archive_archive_free(disk) == CPKT_ARCHIVE_ARCHIVE_OK);
  CHECK(received.hi == -99);
  return 0;
}
