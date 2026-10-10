#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int forbidden(const char *word) {
  static const char *const integer_types[] = {
      "uint8_t", "uint16_t", "uint32_t", "uint64_t",
      "int8_t",  "int16_t",  "int32_t",  "int64_t"};
  size_t i;
  if (strncmp(word, "UA_", 3U) == 0 || strcmp(word, "inline") == 0 ||
      strcmp(word, "_Bool") == 0) {
    return 1;
  }
  for (i = 0U; i < sizeof(integer_types) / sizeof(integer_types[0]); ++i) {
    if (strcmp(word, integer_types[i]) == 0) {
      return 1;
    }
  }
  return 0;
}

static int check(const char *path) {
  FILE *file;
  char *text;
  long length;
  size_t size;
  size_t read_index;
  size_t write_index;
  size_t i;
  int quote;
  int block;
  int line;
  int failed;
  char previous[128];
  file = fopen(path, "rb");
  if (file == NULL || fseek(file, 0L, SEEK_END) != 0 ||
      (length = ftell(file)) < 0L || fseek(file, 0L, SEEK_SET) != 0) {
    if (file != NULL) {
      fclose(file);
    }
    fprintf(stderr, "cannot read public header: %s\n", path);
    return 1;
  }
  size = (size_t)length;
  text = (char *)malloc(size + 1U);
  if (text == NULL || fread(text, 1U, size, file) != size) {
    free(text);
    fclose(file);
    return 1;
  }
  fclose(file);
  text[size] = '\0';
  write_index = 0U;
  for (read_index = 0U; read_index < size; ++read_index) {
    if (text[read_index] == '\\' && text[read_index + 1U] == '\n') {
      ++read_index;
    } else if (text[read_index] == '\\' && text[read_index + 1U] == '\r' &&
               read_index + 2U < size && text[read_index + 2U] == '\n') {
      read_index += 2U;
    } else {
      text[write_index++] = text[read_index];
    }
  }
  size = write_index;
  text[size] = '\0';
  quote = block = line = 0;
  for (i = 0U; i < size; ++i) {
    if (block) {
      if (text[i] == '*' && text[i + 1U] == '/') {
        text[i++] = ' ';
        text[i] = ' ';
        block = 0;
      } else if (text[i] != '\n') {
        text[i] = ' ';
      }
    } else if (line) {
      if (text[i] == '\n') {
        line = 0;
      } else {
        text[i] = ' ';
      }
    } else if (quote) {
      if (text[i] == '\\' && i + 1U < size) {
        ++i;
      } else if (text[i] == quote) {
        quote = 0;
      }
    } else if (text[i] == '"' || text[i] == '\'') {
      quote = text[i];
    } else if (text[i] == '/' && text[i + 1U] == '*') {
      text[i++] = ' ';
      text[i] = ' ';
      block = 1;
    } else if (text[i] == '/' && text[i + 1U] == '/') {
      text[i++] = ' ';
      text[i] = ' ';
      line = 1;
    }
  }
  failed = 0;
  previous[0] = '\0';
  for (i = 0U; i < size;) {
    char word[128];
    size_t count;
    if (text[i] == '#') {
      size_t cursor;
      cursor = i + 1U;
      while (isspace((unsigned char)text[cursor])) {
        ++cursor;
      }
      if (strncmp(text + cursor, "include", 7U) == 0) {
        cursor += 7U;
        while (isspace((unsigned char)text[cursor])) {
          ++cursor;
        }
        if (text[cursor] == '<' || text[cursor] == '"') {
          ++cursor;
          if (strncmp(text + cursor, "open62541/", 10U) == 0 ||
              strncmp(text + cursor, "stdint.h", 8U) == 0 ||
              strncmp(text + cursor, "stdbool.h", 9U) == 0) {
            fprintf(stderr, "%s: upstream/non-C89 include\n", path);
            failed = 1;
          }
        }
      }
    }
    if (text[i] == '"' || text[i] == '\'') {
      quote = text[i++];
      while (i < size && text[i] != quote) {
        if (text[i] == '\\' && i + 1U < size) {
          ++i;
        }
        ++i;
      }
      if (i < size) {
        ++i;
      }
      previous[0] = '\0';
      continue;
    }
    if (!isalpha((unsigned char)text[i]) && text[i] != '_') {
      if (!isspace((unsigned char)text[i])) {
        previous[0] = '\0';
      }
      ++i;
      continue;
    }
    count = 0U;
    do {
      if (count + 1U < sizeof(word)) {
        word[count++] = text[i];
      }
      ++i;
    } while (isalnum((unsigned char)text[i]) || text[i] == '_');
    word[count] = '\0';
    if (forbidden(word) ||
        (strcmp(previous, "long") == 0 && strcmp(word, "long") == 0)) {
      fprintf(stderr, "%s: forbidden C89 facade token: %s\n", path, word);
      failed = 1;
    }
    strcpy(previous, word);
  }
  free(text);
  return failed;
}

int main(int argc, char **argv) {
  int i;
  int failed;
  if (argc < 2) {
    fprintf(stderr, "usage: header_contract <header> [<header> ...]\n");
    return 2;
  }
  failed = 0;
  for (i = 1; i < argc; ++i) {
    failed |= check(argv[i]);
  }
  return failed;
}
