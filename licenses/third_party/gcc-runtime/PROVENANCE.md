# GCC runtime archives

Linux speech SDKs include the selected Bootlin collection's `libstdc++.a` and
`libgcc.a` under `lib/cpkt-cxx/`. These archives remain separate from facade
archives. Consumers use the shipped CMake/pkg-config closure; they do not need
workstation runtime paths.

The pinned Bootlin 2026.08-1 collections use GCC 15.3.0. `LICENSE` and
`COPYING.RUNTIME` are verbatim copies of `COPYING3` and `COPYING.RUNTIME` from
the upstream `releases/gcc-15.3.0` source tag:

- https://gcc.gnu.org/git/?p=gcc.git;a=tree;hb=releases/gcc-15.3.0
- https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-15.3.0/COPYING3
- https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-15.3.0/COPYING.RUNTIME

The package manifest records the actual delivered runtime archive hashes. Darwin
uses its declared system libc++ closure and does not ship these Linux archives.
