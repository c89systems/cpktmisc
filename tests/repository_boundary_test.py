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
            manifest={'components':[{'name':name,'version':'9.8.'+str(index)} for index,name in enumerate(external)]}
            (work/'manifest.json').write_text(json.dumps(manifest))
            source='file(READ "'+str(ROOT/'cmake/components.json')+'" CPKT_INVENTORY)\n'
            source+='include("'+str(ROOT/'cmake/CpktCoreImports.cmake')+'")\n'
            source+='file(READ "'+str(work/'manifest.json')+'" manifest)\ncpkt_load_core_versions("${manifest}")\n'
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
        from cpkt_core import acquire
        (ROOT/'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='missing-pin-',dir=ROOT/'build') as temporary:
            root=Path(temporary);(root/'dependencies').mkdir()
            (root/'dependencies/cpkt.json').write_text(json.dumps({'schema_version':1,'repository':'c89systems/cpkt','version':'0.1.0','targets':{}}))
            with patch('subprocess.run',side_effect=AssertionError('unexpected subprocess/network')):
                with self.assertRaisesRegex(RuntimeError,'no published checksum pin'):acquire(root,'x86_64-linux-gnu')
            self.assertEqual({'dependencies'},set(p.name for p in root.iterdir()))

if __name__=='__main__':unittest.main()
