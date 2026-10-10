#include <cpkt/ffi.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition)                                                       \
  do {                                                                         \
    if (!(condition)) {                                                        \
      fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);          \
      return 1;                                                                \
    }                                                                          \
  } while (0)

static int add(int a, int b) { return a + b; }
static double sum(int count, ...) {
  va_list args;
  double value;
  int i;
  value = 0;
  va_start(args, count);
  for (i = 0; i < count; ++i)
    value += va_arg(args, double);
  va_end(args);
  return value;
}

static void closure_call(cpkt_ffi_ffi_cif *cif, void *result, void **args,
                         void *data) {
  (void)cif;
  *(int *)result = *(int *)args[0] + *(int *)args[1] + *(int *)data;
}

int main(void) {
  cpkt_ffi_ffi_cif cif;
  cpkt_ffi_ffi_type *types[3];
  void *args[3];
  int a, b, adjustment, count;
  cpkt_ffi_ffi_arg result;
  double first, second, total;
  cpkt_ffi_ffi_closure *closure;
  void *code;
  int (*call)(int, int);
  size_t offsets[2];
  cpkt_ffi_ffi_type record;
  cpkt_ffi_ffi_type *elements[3];
  struct pair {
    char first;
    double second;
  } pair;

  a = 13;
  b = 29;
  adjustment = 9;
  types[0] = &CPKT_FFI_ffi_type_sint;
  types[1] = &CPKT_FFI_ffi_type_sint;
  args[0] = &a;
  args[1] = &b;
  CHECK(cpkt_ffi_ffi_type_sint32_ref() == &CPKT_FFI_ffi_type_sint);
  CHECK(cpkt_ffi_ffi_prep_cif(&cif, CPKT_FFI_FFI_DEFAULT_ABI, 2,
                              &CPKT_FFI_ffi_type_sint,
                              types) == CPKT_FFI_FFI_OK);
  result = 0;
  cpkt_ffi_ffi_call(&cif, CPKT_FFI_FFI_FN(add), &result, args);
  CHECK(result == 42);
  closure = cpkt_ffi_ffi_closure_alloc(sizeof(*closure), &code);
  CHECK(closure != NULL && code != NULL);
  CHECK(cpkt_ffi_ffi_prep_closure_loc(closure, &cif, closure_call, &adjustment,
                                      code) == CPKT_FFI_FFI_OK);
  CHECK(sizeof(call) == sizeof(code));
  memcpy(&call, &code, sizeof(call));
  CHECK(call(a, b) == 51);
  cpkt_ffi_ffi_closure_free(closure);

  count = 2;
  first = 1.25;
  second = 2.75;
  types[0] = &CPKT_FFI_ffi_type_sint;
  types[1] = types[2] = &cpkt_ffi_ffi_type_double;
  args[0] = &count;
  args[1] = &first;
  args[2] = &second;
  CHECK(cpkt_ffi_ffi_prep_cif_var(&cif, CPKT_FFI_FFI_DEFAULT_ABI, 1, 3,
                                  &cpkt_ffi_ffi_type_double,
                                  types) == CPKT_FFI_FFI_OK);
  cpkt_ffi_ffi_call(&cif, CPKT_FFI_FFI_FN(sum), &total, args);
  CHECK(total == 4.0);

  memset(&record, 0, sizeof(record));
  record.type = CPKT_FFI_FFI_TYPE_STRUCT;
  elements[0] = &cpkt_ffi_ffi_type_sint8;
  elements[1] = &cpkt_ffi_ffi_type_double;
  elements[2] = NULL;
  record.elements = elements;
  CHECK(cpkt_ffi_ffi_get_struct_offsets(CPKT_FFI_FFI_DEFAULT_ABI, &record,
                                        offsets) == CPKT_FFI_FFI_OK);
  CHECK(offsets[0] == 0 &&
        offsets[1] == (size_t)((char *)&pair.second - (char *)&pair));
  CHECK(record.size == sizeof(pair));
  CHECK(cpkt_ffi_ffi_prep_cif(&cif, (cpkt_ffi_ffi_abi)999, 0,
                              &cpkt_ffi_ffi_type_void,
                              NULL) == CPKT_FFI_FFI_BAD_ABI);
  return 0;
}
