#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
top_cmake="$repo_root/CMakeLists.txt"
deps_cmake="$repo_root/cmake/CpktDependencies.cmake"
package_bundle="$repo_root/cmake/package_bundle.cmake"

require_file_contains() {
  file_path=$1
  expected=$2
  description=$3

  if ! grep -F -- "$expected" "$file_path" >/dev/null 2>&1; then
    printf '%s\nmissing: %s\nin: %s\n' "$description" "$expected" "$file_path" >&2
    exit 1
  fi
}

require_file_contains \
  "$top_cmake" \
  'option(CPKT_SUS_CPU_ONLY "Build the cpkt_sus whisper.cpp dependency set with CPU backends only." ON)' \
  'cpkt_sus CPU-only build option must default ON'

require_file_contains \
  "$top_cmake" \
  'message(FATAL_ERROR "CPKT_SUS_CPU_ONLY=OFF is reserved for a later GPU-backend packaging phase")' \
  'top-level configure must reject GPU backend builds until packaging policy exists'

require_file_contains \
  "$top_cmake" \
  'set(CPKT_SUS_BACKEND_CAPABILITIES "cpu" CACHE INTERNAL "Compiled cpkt_sus whisper.cpp backend capability list.")' \
  'cpkt_sus backend capability metadata must report cpu for the first implementation'

require_file_contains \
  "$deps_cmake" \
  'message(FATAL_ERROR "cpkt_sus currently supports only CPU-only whisper.cpp dependency builds")' \
  'dependency build must reject non-CPU-only whisper.cpp builds'

for cmake_arg in \
    '-DWHISPER_BUILD_TESTS=OFF' \
    '-DWHISPER_BUILD_EXAMPLES=OFF' \
    '-DWHISPER_BUILD_SERVER=OFF' \
    '-DWHISPER_CURL=OFF' \
    '-DWHISPER_SDL2=OFF' \
    '-DWHISPER_COREML=OFF' \
    '-DWHISPER_COREML_ALLOW_FALLBACK=OFF' \
    '-DWHISPER_OPENVINO=OFF' \
    '-DGGML_NATIVE=OFF' \
    '-DGGML_OPENMP=OFF' \
    '-DGGML_METAL=OFF' \
    '-DGGML_BLAS=OFF' \
    '-DGGML_ACCELERATE=OFF' \
    '-DGGML_CUDA=OFF' \
    '-DGGML_HIP=OFF' \
    '-DGGML_VULKAN=OFF' \
    '-DGGML_OPENCL=OFF' \
    '-DGGML_SYCL=OFF' \
    '-DGGML_RPC=OFF' \
    '-DGGML_BACKEND_DL=OFF' \
    '-DGGML_CPU_ALL_VARIANTS=OFF'; do
  require_file_contains \
    "$deps_cmake" \
    "$cmake_arg" \
    "whisper.cpp dependency build must keep first-release CPU-only flag: $cmake_arg"
done

mkdir -p "$repo_root/build"
python3 - "$repo_root" <<'PYTEST'
import json,pathlib,shutil,subprocess,sys,tempfile
r=pathlib.Path(sys.argv[1]);d=json.loads((r/'cmake/components.json').read_text())
f=d['components']['whisper']['package']['facades'][0]
assert f['features']['backend_capabilities']=='CPKT_SUS_BACKEND_CAPABILITIES'
# Run the current native component encoder against synthetic producer data.
# No SDK configure, dependency acquisition or published core pin is involved.
with tempfile.TemporaryDirectory(prefix='sus-feature-metadata-',dir=r/'build') as temporary:
 root=pathlib.Path(temporary);(root/'cmake').mkdir()
 shutil.copyfile(r/'cmake/CpktDependencies.cmake',root/'cmake/CpktDependencies.cmake')
 for name in d['components']['whisper']['recipe_inputs']:
  path=root/name;path.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(r/name,path)
 producer=root/'build/fixture/misc/producer';producer.mkdir(parents=True)
 key=d['components']['whisper']['package']['version_variable']
 (producer/'CMakeCache.txt').write_text(key+':STRING=fixture\n')
 driver=root/'metadata.cmake'
 driver.write_text(
  'set(CMAKE_SOURCE_DIR "'+str(root)+'")\n'
  'set(CPKT_GROUP misc)\nset(CPKT_TARGET_ID fixture)\n'
  'set(CPKT_ACTIVE_COMPONENTS whisper)\n'
  'file(READ "'+str(r/'cmake/components.json')+'" CPKT_INVENTORY)\n'
  'include("'+str(r/'cmake/CpktPackageMetadata.cmake')+'")\n'
  'cpkt_package_component_metadata(metadata)\n'
  'file(WRITE "'+str(root/'metadata.json')+'" "${metadata}")\n')
 for capability in ('cpu','fixture-capability'):
  result=subprocess.run(['cmake','-DCPKT_SUS_BACKEND_CAPABILITIES='+capability,'-P',str(driver)],capture_output=True,text=True)
  assert result.returncode==0,result.stdout+result.stderr
  records=json.loads((root/'metadata.json').read_text())
  assert len(records)==1 and records[0]['name']=='whisper',records
  assert records[0]['features']['backend_capabilities']==capability,records
 result=subprocess.run(['cmake','-P',str(driver)],capture_output=True,text=True)
 assert result.returncode and 'Missing compiled facade feature: whisper/backend_capabilities' in result.stderr,result.stdout+result.stderr
assert "whisper['features'].get('backend_capabilities')!='cpu'" in (r/'scripts/cpkt_sdk_consumer.py').read_text()
assert any('cpkt_sus_backend_capabilities' in (r/i['source']).read_text() and '"cpu"' in (r/i['source']).read_text() for i in d['installed_consumers'].values() if i.get('pc')=='cpkt-sus')
print('Native SUS metadata preserves supplied backend capabilities and rejects missing compiled features')
PYTEST
