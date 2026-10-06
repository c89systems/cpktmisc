#!/usr/bin/env python3
"""Falsifiable repository ownership, provider identity and offline SDK contracts."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from cpkt_inventory import load,components_for,REPOSITORY_GROUP
from cpkt_packages import validator,artifacts


def canonical(item):return json.dumps(item,sort_keys=True,separators=(',',':')).encode()
def sha(item):return hashlib.sha256(item).hexdigest()

class Repository(unittest.TestCase):
    def test_dependency_graph_has_no_owned_sibling(self):
        data=load(ROOT)
        self.assertEqual({REPOSITORY_GROUP},set(data['groups']))
        names=components_for(data,'all')
        self.assertTrue(names)
        self.assertEqual(set(names),{name for name,item in data['components'].items() if item['group']==REPOSITORY_GROUP})
        for name in names:
            for edge in data['components'][name]['dependencies']:
                self.assertIn(data['components'][edge]['group'],(REPOSITORY_GROUP,'core'))
                if data['components'][edge]['group']!=REPOSITORY_GROUP:self.assertEqual('cpkt',data['components'][edge]['external'])

    def test_core_versions_are_read_from_manifest(self):
        data=load(ROOT)
        external={name:item for name,item in data['components'].items() if item.get('external')=='cpkt'}
        with tempfile.TemporaryDirectory(prefix='core-version-import-',dir=ROOT/'build') as temporary:
            work=Path(temporary)
            manifest={'package_id':'a'*64,'components':[{'name':name,'version':'9.8.'+str(index)} for index,name in enumerate(external)]}
            (work/'manifest.json').write_text(json.dumps(manifest))
            source='file(READ "'+str(ROOT/'cmake/components.json')+'" CPKT_INVENTORY)\n'
            source+='include("'+str(ROOT/'cmake/CpktCoreImports.cmake')+'")\n'
            source+='file(READ "'+str(work/'manifest.json')+'" manifest)\ncpkt_load_core_versions("${manifest}")\n'
            source+='cpkt_register_core_contracts("${manifest}")\n'
            for name in external:
                source+='get_property(id GLOBAL PROPERTY "CPKT_DEPENDENCY_CONTRACT_'+name+'")\n'
                source+='if(NOT id STREQUAL "'+('a'*64)+'")\nmessage(FATAL_ERROR "Missing imported contract")\nendif()\n'
            for index,item in enumerate(external.values()):
                variable=item['package']['version_variable']
                source+='if(NOT "${'+variable+'}" STREQUAL "9.8.'+str(index)+'")\nmessage(FATAL_ERROR "Stale imported version '+variable+'")\nendif()\n'
            driver=work/'versions.cmake';driver.write_text(source)
            result=subprocess.run(['cmake','-P',str(driver)],capture_output=True,text=True)
            self.assertEqual(0,result.returncode,result.stdout+result.stderr)
            manifest['components'].pop();(work/'manifest.json').write_text(json.dumps(manifest))
            result=subprocess.run(['cmake','-P',str(driver)],capture_output=True,text=True)
            self.assertNotEqual(0,result.returncode)
            self.assertIn('requires exactly one version',result.stderr)
            manifest['components'].append(manifest['components'][0]);(work/'manifest.json').write_text(json.dumps(manifest))
            result=subprocess.run(['cmake','-P',str(driver)],capture_output=True,text=True)
            self.assertNotEqual(0,result.returncode)
            self.assertIn('requires exactly one version',result.stderr)

    def test_explicit_core_acquisition_restores_archive_without_replacing_install(self):
        from native_lifecycle_fixture import seed,environment,archive
        from package_producer_reuse_test import prerequisite
        from cpkt_receipts import tree_identity
        from cpkt_core import cached_archive
        with tempfile.TemporaryDirectory(prefix='core-archive-restoration-',dir=ROOT/'build') as temporary:
            root=Path(temporary);seed(root);prerequisite(root)
            target='x86_64-linux-gnu';prefix=root/'.cache/cpkt'/target/'install'
            original=tree_identity(prefix)
            package=root/'build/archive-payload'/('cpkt-0.1.0-'+target)
            package.parent.mkdir(parents=True);shutil.copytree(prefix,package)
            source=root/'build/local-core.tar.gz';archive(package,source)
            source_bytes=source.read_bytes()
            pins=root/'dependencies/cpkt.json';data=json.loads(pins.read_text())
            digest=sha(source_bytes);data['targets'][target]['sha256']=digest
            pins.write_text(json.dumps(data))
            cache=root/'build/synthetic-shared-cache'
            real_cmake=shutil.which('cmake');wrapper=root/'build/cmake-transport'
            wrapper.write_text('#!'+sys.executable+'\nimport json,pathlib,subprocess,sys\n'
                'arguments=sys.argv[1:]\n'
                'if "-DCPKT_CORE_ACTION=acquire" in arguments:\n'
                ' index=next(i for i,arg in enumerate(arguments) if arg.startswith("-DCPKT_CORE_PIN="))\n'
                ' pin=pathlib.Path(arguments[index].split("=",1)[1]);data=json.loads(pin.read_text())\n'
                ' assert data["url"].startswith("https://github.com/c89systems/cpkt/releases/download/")\n'
                ' data["url"]='+repr(source.as_uri())+'\n'
                ' local=pin.with_name("transport-pin.json");local.write_text(json.dumps(data))\n'
                ' arguments[index]="-DCPKT_CORE_PIN="+str(local)\n'
                'raise SystemExit(subprocess.call(['+repr(real_cmake)+',*arguments]))\n')
            wrapper.chmod(0o755)
            variables=environment();variables.update(CMAKE=str(wrapper),CPKT_DEPENDENCY_CACHE=str(cache))
            def acquire():
                return subprocess.run(['bash',str(root/'scripts/core-dependency.sh'),target],
                    env=variables,capture_output=True,text=True)
            result=acquire()
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            with patch.dict(os.environ,CPKT_DEPENDENCY_CACHE=str(cache)):
                archived=cached_archive(root,target)
            self.assertEqual(archived.read_bytes(),source_bytes)
            self.assertEqual(original,tree_identity(prefix))
            stat=archived.stat();source.unlink()
            result=acquire()
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual(archived.stat().st_mtime_ns,stat.st_mtime_ns)
            self.assertEqual(original,tree_identity(prefix))
            source.write_bytes(source_bytes);archived.write_bytes(b'corrupt archive')
            result=acquire()
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual(archived.read_bytes(),source_bytes)
            self.assertEqual(original,tree_identity(prefix))
            archived.unlink();source.unlink()
            result=acquire()
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(original,tree_identity(prefix))

    def test_native_recipes_use_imported_core_paths_and_mqtt_support(self):
        with tempfile.TemporaryDirectory(prefix='misc-core-paths-',dir=ROOT/'build') as temporary:
            work=Path(temporary);core=work/'sdk'
            support=core/'share/cpkt/mqtt-c'
            for name in ('src/mqtt.c','src/mqtt_pal.c','include/mqtt.h','include/mqtt_pal.h'):
                path=support/name;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text('synthetic MQTT support '+name)
            toolchain=work/'toolchain';(toolchain/'bin').mkdir(parents=True)
            for platform,suffix in (('Linux','.so'),('Darwin','.dylib')):
                with self.subTest(platform=platform):
                    root=work/platform;root.mkdir()
                    records=root/'records';records.mkdir()
                    source='cmake_minimum_required(VERSION 3.21)\nproject(prefixes NONE)\n'
                    source+='include("'+str(ROOT/'cmake/CpktDependencies.cmake')+'")\n'
                    source+='set(CPKT_CORE_PREFIX "'+str(core)+'")\nset(CPKT_BUILD_DEPENDENCIES ON)\n'
                    source+='set(CMAKE_SYSTEM_NAME '+platform+')\nset(CMAKE_SHARED_LIBRARY_SUFFIX '+suffix+')\nset(CMAKE_STATIC_LIBRARY_SUFFIX .a)\n'
                    source+='set(CPKT_TOOLCHAIN_ROOT "'+str(toolchain)+'")\n'
                    for key in ('C_COMPILER','CXX_COMPILER','LINKER','AR','RANLIB','STRIP','NM','OBJCOPY','OBJDUMP','ADDR2LINE','READELF'):
                        source+='set(CMAKE_'+key+' "/synthetic/bin/tool")\n'
                    source+='set(CPKT_DEPENDENCY_BUILD_ROOT "'+str(root/'deps-build')+'")\nset(CPKT_EXTERNAL_ROOT "'+str(root/'deps')+'")\n'
                    source+='function(cpkt_component_producer_prerequisites output)\nset(${output} "" PARENT_SCOPE)\nendfunction()\n'
                    source+='function(cpkt_cached_external_project_add name)\nfile(WRITE "'+str(records)+'/${name}" "${ARGV}")\nadd_custom_target(${name})\nendfunction()\n'
                    source+='cpkt_add_libpng()\ncpkt_add_libharu()\ncpkt_add_open62541()\n'
                    source+='cpkt_append_external_pkg_config_env_args(env)\nfile(WRITE "'+str(records/'pkgconfig')+'" "${env}")\n'
                    (root/'CMakeLists.txt').write_text(source)
                    result=subprocess.run(['cmake','-S',str(root),'-B',str(root/'build')],capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                    png=(records/'cpkt_libpng_project').read_text()
                    for argument in ('-DZLIB_ROOT='+str(core),'-DZLIB_INCLUDE_DIR='+str(core)+'/include',
                                     '-DZLIB_LIBRARY='+str(core)+'/lib/libz'+suffix):
                        self.assertIn(argument,png)
                    for variant,library_suffix in (('shared',suffix),('static','.a')):
                        haru=(records/('cpkt_libharu_'+variant+'_project')).read_text()
                        self.assertIn('-DZLIB_INCLUDE_DIR='+str(core)+'/include',haru)
                        self.assertIn('-DZLIB_LIBRARY='+str(core)+'/lib/libz'+library_suffix,haru)
                        self.assertIn('-DPNG_LIBRARY='+str(root/'deps/libpng/install/lib/libpng16')+library_suffix,haru)
                        opcua=(records/('cpkt_open62541_'+variant+'_project')).read_text()
                        self.assertIn('-DOpenSSL_DIR='+str(core)+'/lib/cmake/OpenSSL',opcua)
                        self.assertIn('-DOPENSSL_USE_STATIC_LIBS:BOOL='+('ON' if variant=='static' else 'OFF'),opcua)
                        arguments=opcua.split(';');index=arguments.index('copy_directory')
                        origin,destination=arguments[index+1:index+3]
                        self.assertEqual(origin,str(support))
                        self.assertEqual(destination,str(root/('deps-build/open62541/src-'+variant+'/deps/mqtt-c')))
                        self.assertIn('-DUA_FILE_MQTT='+destination+'/src/mqtt.c',opcua)
                        # Execute only the recorded support-file copy, never a product step.
                        subprocess.run(['cmake','-E','copy_directory',origin,destination],check=True)
                        for path in support.rglob('*'):
                            if path.is_file():self.assertEqual(path.read_bytes(),(Path(destination)/path.relative_to(support)).read_bytes())
                    pkgconfig=(records/'pkgconfig').read_text()
                    self.assertIn('PKG_CONFIG_LIBDIR='+str(core)+'/lib/pkgconfig:'+str(core)+'/share/pkgconfig:'+str(root/'deps/libpng/install/lib/pkgconfig'),pkgconfig)

    def test_hardening_inputs_fail_before_build_when_missing_or_empty(self):
        from cpkt_inventory import validate_inputs
        data=load(ROOT)
        policy=data['groups'][REPOSITORY_GROUP]['hardening']
        paths=[policy['memcheck_suppression'],*policy['fuzz_seeds']]
        self.assertEqual(REPOSITORY_GROUP!='db',bool(policy['fuzz_seeds']))
        (ROOT/'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='hardening-input-preflight-',dir=ROOT/'build') as temporary:
            root=Path(temporary)
            for name in validate_inputs(ROOT,data):
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(ROOT/name,path)
            for name in paths:
                with self.subTest(missing=name):
                    path=root/name;original=path.read_bytes();path.unlink()
                    with self.assertRaisesRegex(RuntimeError,name):validate_inputs(root,data)
                    self.assertFalse((root/'.cache').exists())
                    self.assertFalse((root/'build').exists())
                    path.write_bytes(original)
            for name in policy['fuzz_seeds']:
                with self.subTest(empty=name):
                    path=root/name;original=path.read_bytes();path.write_bytes(b'')
                    with self.assertRaisesRegex(RuntimeError,'fuzz seed must be nonempty'):
                        validate_inputs(root,data)
                    path.write_bytes(original)

    def test_pic_requirement_distinguishes_packaging_from_hardening(self):
        data=load(ROOT)
        (ROOT/'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='pic-coverage-policy-',dir=ROOT/'build') as temporary:
            root=Path(temporary);(root/'cmake').mkdir()
            (root/'cmake/components.json').write_text(json.dumps({
                'tests':{'static_archive_pic_link':data['tests']['static_archive_pic_link']}}))
            for name,facade_only,registered,success in (
                    ('hardening','ON',False,True),
                    ('ordinary-missing','OFF',False,False),
                    ('ordinary-covered','OFF',True,True)):
                source=root/name;source.mkdir()
                source.joinpath('CMakeLists.txt').write_text(
                    'cmake_minimum_required(VERSION 3.21)\nproject(coverage NONE)\nenable_testing()\n'
                    'set(CPKT_BUILD_TESTS ON)\nset(CPKT_CAN_RUN_TARGET_EXECUTABLES ON)\n'
                    'set(CPKT_FACADE_ONLY '+facade_only+')\n'+
                    ('add_test(NAME static_archive_pic_link COMMAND cmake -E true)\n' if registered else '')+
                    'set(CPKT_GROUP '+REPOSITORY_GROUP+')\nfile(READ "'+str(root/'cmake/components.json')+'" CPKT_INVENTORY)\ninclude("'+str(ROOT/'cmake/CpktTestInventory.cmake')+'")\ncpkt_assert_test_inventory()\n')
                result=subprocess.run(['cmake','-S',str(source),'-B',str(root/(name+'-build'))],capture_output=True,text=True)
                self.assertEqual(success,result.returncode==0,result.stdout+result.stderr)
                if not success:self.assertIn('Missing required inventory case: static_archive_pic_link',result.stderr)

    def test_owned_pic_policy_rejects_each_missing_recipe_setting(self):
        import re
        data=load(ROOT)
        recipe=(ROOT/'cmake/CpktDependencies.cmake').read_text()
        policy=ROOT/'tests/static_dependency_pic_policy_test.sh'
        result=subprocess.run(['bash',str(policy),str(ROOT)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        with tempfile.TemporaryDirectory(prefix='owned-pic-policy-',dir=ROOT/'build') as temporary:
            root=Path(temporary);(root/'cmake').mkdir()
            for component in components_for(data,'all'):
                function=data['components'][component]['recipe_functions'][-1]
                body=re.search(r'function\('+re.escape(function)+r'\).*?endfunction\(\)',recipe,re.S)
                self.assertIsNotNone(body,function)
                settings=list(re.finditer(r'-fPIC|-DCMAKE_POSITION_INDEPENDENT_CODE=ON',body.group()))
                self.assertTrue(settings,component+' has no owned PIC coverage')
                for index,setting in enumerate(settings):
                    with self.subTest(component=component,setting=index):
                        start=body.start()+setting.start();end=body.start()+setting.end()
                        (root/'cmake/CpktDependencies.cmake').write_text(recipe[:start]+recipe[end:])
                        result=subprocess.run(['bash',str(policy),str(root)],capture_output=True,text=True)
                        self.assertNotEqual(result.returncode,0,component+' missing PIC accepted')
                        self.assertIn(function+' must retain',result.stderr)

    def test_release_asset_inventory_is_one_producer(self):
        data=load(ROOT);project=data['project']
        expected={project+'-1.2.3-'+target+'.tar.gz' for target in data['package_targets']}
        expected|={project+'-1.2.3.tar.gz',project+'-1.2.3-arm64-apple-darwin-smoke-test.zip'}
        self.assertEqual(expected,set(artifacts('1.2.3','release')))
        self.assertEqual(9,len(expected))

    def test_independent_version_requires_exact_core_identity(self):
        (ROOT/'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='provider-identity-',dir=ROOT/'build') as temporary:
            prefix=Path(temporary);manifests={}
            for group,version in (('core','0.1.0'),('db','0.7.2')):
                path=prefix/group/'payload';path.parent.mkdir();path.write_bytes(group.encode());path.chmod(0o644)
                item={'schema_version':1,'group':group,'release_version':version,'target_id':'x86_64-linux-gnu','libc':'gnu','macos_deployment_target':None,
                    'components':[{'name':group,'version':'1','source_sha256':'a'*64,'features':{},'abi':{'soname':'lib'+group+'.so.0'}}],
                    'files':[{'path':group+'/payload','type':'file','mode':'0644','sha256':sha(path.read_bytes())}],
                    'requires_core':None if group=='core' else {k:manifests['core'][k] for k in ('package_id','release_version','target_id')}}
                item['package_id']=sha(canonical(item));manifests[group]=item
                destination=prefix/'share/cpkt/packages'/(''+group+'.json');destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(canonical(item));destination.chmod(0o644)
            self.assertEqual({'core','db'},set(validator.validate(prefix,['core','db'],'0.7.2','x86_64-linux-gnu')))
            item=copy.deepcopy(manifests['db']);item['requires_core']['package_id']='f'*64;item.pop('package_id');item['package_id']=sha(canonical(item))
            (prefix/'share/cpkt/packages/db.json').write_bytes(canonical(item))
            with self.assertRaisesRegex(ValueError,'exact core'):validator.validate(prefix,['core','db'])
            (prefix/'share/cpkt/packages/db.json').write_bytes(canonical(manifests['db']))
            (prefix/'core/payload').write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError,'content/mode'):validator.validate(prefix,['core','db'])

    @unittest.skipIf(REPOSITORY_GROUP=='core','core has no external provider')
    def test_missing_pin_fails_before_acquisition_or_mutation(self):
        from native_lifecycle_fixture import seed,environment
        from cpkt_receipts import tree_identity
        (ROOT/'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='missing-pin-',dir=ROOT/'build') as temporary:
            root=Path(temporary);seed(root);(root/'dependencies').mkdir()
            (root/'dependencies/cpkt.json').write_text(json.dumps({'schema_version':1,'repository':'c89systems/cpkt','version':'0.1.0','targets':{}}))
            marker=root/'acquisition-started';cmake=root/'cmake-probe.sh'
            cmake.write_text('#!/bin/sh\ncase "$*" in *CPKT_CORE_ACTION=acquire*) touch '+str(marker)+'; exit 47 ;; esac\nexec '+shutil.which('cmake')+' "$@"\n');cmake.chmod(0o755)
            before=tree_identity(root)
            result=subprocess.run(['bash',str(root/'scripts/core-dependency.sh'),'x86_64-linux-gnu'],env=dict(environment(),CMAKE=str(cmake)),capture_output=True,text=True)
            self.assertNotEqual(0,result.returncode);self.assertIn('no published checksum pin',result.stderr)
            self.assertFalse(marker.exists());self.assertFalse((root/'build').exists());self.assertFalse((root/'.cache').exists())
            self.assertEqual(before,tree_identity(root))

if __name__=='__main__':unittest.main()
