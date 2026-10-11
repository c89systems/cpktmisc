#include <cpkt/sus.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  unsigned long i;
  unsigned long defaults;
  cpkt_sus_model_entry entry;
  defaults = 0UL;
  puts("name\tprovider\tfilename\tsource_url\tsha256\tsize_"
       "bytes\tlicense\tquantization\tis_default");
  for (i = 0UL; i < cpkt_sus_model_catalog_count(); ++i) {
    if (cpkt_sus_model_catalog_entry(i, &entry) != CPKT_SUS_OK ||
        strncmp(entry.source_url, "https://huggingface.co/", 23U) != 0 ||
        strlen(entry.sha256) != 64U ||
        strspn(entry.sha256, "0123456789abcdef") != 64U ||
        entry.size_bytes == 0UL) {
      return 1;
    }
    if (strncmp(entry.provider, "KBLab/", 6U) == 0 &&
        (strcmp(entry.filename, "ggml-model.bin") == 0 ||
         strcmp(entry.filename, "ggml-model-q5_0.bin") == 0)) {
      return 4;
    }
    if (entry.is_default) {
      ++defaults;
      if (strcmp(entry.name, "tiny") != 0) {
        return 2;
      }
    }
    printf("%s\t%s\t%s\t%s\t%s\t%lu\t%s\t%s\t%d\n", entry.name, entry.provider,
           entry.filename, entry.source_url, entry.sha256, entry.size_bytes,
           entry.license, entry.quantization, entry.is_default);
  }
  return defaults == 1UL ? 0 : 3;
}
