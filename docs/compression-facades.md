# Archive, compression, foreign calls and YAML

cpktmisc bundles libffi 3.8.0, libarchive 3.8.9, zstd 1.5.7, libyaml 0.2.5,
bzip2 1.0.8, xz/liblzma 5.8.4, LZ4 1.10.0 and LZO 2.10. The archive library
uses these bundled codecs and the independently installed core SDK's zlib,
OpenSSL and libxml2.
Its BLAKE2 implementation is built in. Filters that upstream implements by
launching an external program retain that upstream requirement.

libyaml and bzip2 expose their upstream C89 headers. libffi, libarchive, zstd,
liblzma, LZ4 and LZO also provide standalone `<cpkt/ffi.h>`, `<cpkt/archive.h>`,
`<cpkt/zstd.h>`, `<cpkt/lzma.h>`, `<cpkt/lz4.h>` and `<cpkt/lzo.h>` facades.
The generated declarations include advanced, deprecated and static-only APIs.
Every target's declarations are generated from its installed pinned headers
and system headers. Upstream headers and static/shared libraries also ship.

The public surface includes functions, typedefs, callback signatures, public
variables, record members, enum values and consumer macros. CTest independently
parses the installed native headers, compiles references to every facade binding
and record member (including nested records), checks enum values and macro
availability, and verifies every binding in both static and shared libraries.
The probes compile under strict C89 and C++98. Negative fixtures prove that a
missing macro, wrong enum value, missing type, member, declaration or library export
fails the gate. Native libyaml and bzip2 headers pass the same language and
symbol checks without requiring facades. Compiler/configuration helpers and
header guards do not introduce additional callable APIs.

For the pinned x86_64 GNU configuration, the public function inventories are:

| Dependency | Public functions | Consumer header |
| --- | ---: | --- |
| libffi 3.8.0 | 30 | `cpkt/ffi.h` |
| libarchive 3.8.9 | 453 | `cpkt/archive.h` |
| zstd 1.5.7, including dictionary and error APIs | 187 | `cpkt/zstd.h` |
| liblzma 5.8.4 | 114 | `cpkt/lzma.h` |
| LZ4 1.10.0, including frame and file APIs | 117 | `cpkt/lz4.h` |
| LZO 2.10 | 93 | `cpkt/lzo.h` |
| libyaml 0.2.5 | 48 | `yaml.h` |
| bzip2 1.0.8 | 24 | `bzlib.h` |

Target-dependent declarations are checked against each target's own headers;
these counts are not substituted for that comparison. PDF separately covers
libHaru's 290 public functions. OPC UA checks its enabled public declaration
contract. Audio and speech expose the product APIs defined in
`audio-sus-facade-spec.md`; they do not claim the complete miniaudio,
whisper.cpp or ggml upstream surfaces.

Facade function names prefix the complete native name with `cpkt_LIBRARY_`,
for example `cpkt_zstd_ZSTD_compress`. Types use the same prefix; constants
and macros use `CPKT_LIBRARY_`. This preserves an unambiguous mapping to the
upstream documentation. Upstream ownership, allocator, callback, error and
buffer contracts apply unless an adaptation is described below. Native public
variables are borrowed lvalues backed by their actual native storage.

`CPKT_FFI_FFI_CL(function)` uses `cpkt_ffi_closure_pointer` to perform the
native function-to-closure pointer conversion inside the bridge, keeping the
caller expression valid in strict C89. Reusable libffi call plans remain
caller-owned, and their CIF must outlive the plan. Liblzma's VLI and decode
memory-limit pointer arguments preserve both input and updated output values,
including incremental VLI decoding and required-memory results on failure.

`cpkt_compression_u64` contains unsigned 32-bit `lo` and `hi` members.
`cpkt_compression_i64` contains unsigned `lo` and signed `hi`. These retain
all bits without requiring C99 integer types. Facade constructors and literal
macros produce these values; comparison uses both words. Struct fields,
input/output arguments, sizes, identifiers, offsets and callbacks translate
at the boundary. Initialize input and in/out records to zero before filling
their documented fields. Output-only VLI values, property-decode option pointers
and block-header filter arrays may be uninitialized, as permitted by upstream.
Filter terminator option pointers are ignored. Native compiler/configuration helpers have no ownership
or runtime behavior; public constants and operation macros remain available.
Values retain the native target's range; a target with 32-bit `time_t` retains
that time range. Native archive consumers receive `_FILE_OFFSET_BITS=64` from
the package metadata so their stat layout agrees with the bundled library.

Libarchive seek, skip and user/group lookup callbacks receive full-width
values. Client data passes through unchanged. Upstream still controls when
registered cleanup callbacks run. Disk lookup cleanup callbacks are suppressed
when the original client data is NULL, including replacement and destruction.
`cpkt_archive_archive_entry_stat(entry,
&record)` returns `ARCHIVE_OK` with a complete copied target stat record, or
`ARCHIVE_FATAL` when the native view or destination is unavailable. This copy
is caller-owned. `archive_entry_copy_stat` and the disk entry reader accept
that same record. Error formatting materializes its error message, as the
upstream error API does; archive data is not staged by the facade.
Passing NULL as the error format sets the error number and clears its message,
matching the native API.

Liblzma streams retain private native stream and block storage until
`cpkt_lzma_lzma_end`. Do not copy an active stream. Caller-owned block and
allocator records retain their upstream lifetimes. Filter arrays have the
upstream maximum of four filters followed by the unknown-ID sentinel.
Reinitializing a stream retires its old borrowed block once the native coder
is replaced or ended; an early failure that keeps the old coder active retains
the block. Filter-copy and filter-string parse failures preserve the caller's
destination records, including allocation failures.
NULL stream handles report `LZMA_PROG_ERROR`; `LZMA_MEM_ERROR` indicates an
allocation failure.
The index iterator exposes its stream flags as a copied value plus
`flags_present`, preserving the optional upstream flags view without
borrowing an incompatible record layout. Unsuccessful next and locate searches
leave the complete iterator unchanged, including its copied flags.
Reserved and private fields remain
implementation storage and must not be changed while an operation is active.

LZO's assembly-named decoder declarations have no upstream assembly
implementation on the shipped architectures. Their facade operations use
the corresponding upstream portable decoder, including the safe decoder
for safe variants. The decompression and error contracts are retained.

Streaming calls operate directly on caller buffers and upstream state.
Libarchive callback input, zstd streaming, liblzma streaming and LZ4 file
operations retain incremental flow. Backend-internal buffering follows the
upstream API; the facade introduces no full-payload buffering or spooling.

Static and shared facade libraries are `libcpkt_LIBRARY`. Public CMake
packages are `CpktFfiFacade`, `CpktArchiveFacade`, `CpktZstdFacade`,
`CpktLzmaFacade`, `CpktLz4Facade` and `CpktLzoFacade`, with `cpkt::LIBRARY`
and `cpkt::LIBRARY_shared` targets. pkg-config names are `cpkt-LIBRARY`;
use `--static` for static consumers. The native libraries retain their ABI
identities. Each new facade starts at independent ABI major 0.

Install misc and a compatible core into separate prefixes. Before linking through
pkg-config, run the installed `lib/cmake/CpktMisc/pkg-config` CMake project with
`CPKT_SDK_PREFIX` pointing to misc and the same pkg-config executable and
environment as the link query. It checks the selected core's compatibility floor,
target and payload; CMake package discovery performs these checks automatically.

LZO is GPL version 2 or later. Other upstream license texts, and XZ's
additional notices, accompany the SDK under
`share/doc/cpkt/misc/third_party/`. The executable examples in
`tests/*_facade_test.c` exercise calls, closures, codec round trips,
streaming, full-width values, callbacks, cleanup and failure results.
