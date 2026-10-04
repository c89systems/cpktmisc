#!/usr/bin/env python3
"""Acquire or read a checksum-pinned published core SDK; never build core."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def validator(root):
    spec=importlib.util.spec_from_file_location('core_sdk_validator',root/'scripts/validate-sdk.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def pin(root,target):
    data=json.loads((root/'dependencies/cpkt.json').read_text())
    if set(data)!={'schema_version','repository','version','targets'} or data['schema_version']!=1 or data['repository']!='c89systems/cpkt' or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',data['version']):
        raise RuntimeError('invalid dependencies/cpkt.json schema/provider/version')
    if target not in data['targets']:
        raise RuntimeError('core '+data['version']+' has no published checksum pin for '+target+'; populate dependencies/cpkt.json from the verified cpkt release')
    item=data['targets'][target]
    name='cpkt-'+data['version']+'-'+target+'.tar.gz'
    expected='https://github.com/c89systems/cpkt/releases/download/v'+data['version']+'/'+name
    if set(item)!={'url','sha256','package_id'} or item['url']!=expected or any(not re.fullmatch('[0-9a-f]{64}',item[key]) for key in ('sha256','package_id')):
        raise RuntimeError('invalid core archive URL/digests for '+target)
    return dict(item,version=data['version'],name=name)


def prefix(root,target):
    return root/'.cache/cpkt'/target/'install'


def validate(root,target):
    item=pin(root,target)
    path=prefix(root,target)
    tool=validator(root)
    tool.validate(path,['core'],item['version'],target,{'core':item['package_id']})
    return tool.load_manifest(path,'core')


def cached_archive(root,target):
    item=pin(root,target)
    shared=Path(os.environ.get('CPKT_DEPENDENCY_CACHE',str(Path(os.environ.get('XDG_CACHE_HOME',str(Path.home()/'.cache')))/'cpkt/deps')))
    directory=shared/'archives/sha256'/item['sha256']
    for path in sorted(directory.glob('*')):
        if path.is_file() and not path.name.startswith('.') and validator(root).sha(path)==item['sha256']:
            return path
    raise RuntimeError('verified core source archive absent from shared cache; run make deps-core')


def imported_component(root,target,name):
    manifest=validate(root,target)
    records=[value for value in manifest['components'] if value['name']==name]
    if len(records)!=1:raise RuntimeError('pinned core omits component: '+name)
    return {'schema_version':1,'status':'passed','kind':'external-component','group':'core',
            'component':name,'target':target,'input_id':manifest['package_id'],
            'package_id':manifest['package_id'],'record':records[0]}


def acquire(root,target):
    # Validate all input before creating directories or performing acquisition.
    item=pin(root,target)
    try:
        validate(root,target)
        link_components(root,target)
        return prefix(root,target)
    except (OSError,ValueError,RuntimeError):
        pass
    from cpkt_operation import delegated
    from cpkt_inventory import REPOSITORY_GROUP
    delegated(root,REPOSITORY_GROUP)
    workspace=root/'build/core-acquisition'/target
    if workspace.is_symlink():raise RuntimeError('core acquisition workspace must not be a symlink')
    workspace.mkdir(parents=True,exist_ok=True)
    driver=workspace/'acquire.cmake'
    # Bracket arguments preserve paths literally and reject the terminator.
    def literal(value):
        text=str(value)
        if ']==]' in text:raise RuntimeError('unsafe CMake bracket argument')
        return '[==['+text+']==]'
    driver.write_text('include('+literal(root/'cmake/CpktDependencyArchiveCache.cmake')+')\n'
        +'cpkt_initialize_dependency_cache()\nset(CPKT_DEPENDENCY_CACHE_LOCK_TIMEOUT 120)\n'
        +'cpkt_acquire_dependency_archive(archive NAME '+literal(item['name'])
        +' SHA256 '+literal(item['sha256'])+' URLS '+literal(item['url'])+')\n'
        +'file(WRITE '+literal(workspace/'archive-path')+' "${archive}")\n')
    subprocess.run(['cmake','-P',str(driver)],cwd=root,check=True)
    archive=Path((workspace/'archive-path').read_text())
    if validator(root).sha(archive)!=item['sha256']:raise RuntimeError('core archive checksum changed')
    from cpkt_packages import safe_extract
    stage=Path(tempfile.mkdtemp(prefix='extract-',dir=workspace))
    try:
        extracted=safe_extract(archive,stage,'cpkt-'+item['version']+'-'+target)
        tool=validator(root)
        tool.validate(extracted,['core'],item['version'],target,{'core':item['package_id']})
        destination=prefix(root,target)
        destination.parent.mkdir(parents=True,exist_ok=True)
        if destination.is_symlink():raise RuntimeError('core installation must not be a symlink')
        if destination.exists():shutil.rmtree(destination)
        extracted.rename(destination)
    finally:
        shutil.rmtree(stage)
    validate(root,target)
    link_components(root,target)
    return prefix(root,target)


def link_components(root,target):
    """Expose read-only prerequisite locations used by existing owned recipes."""
    from cpkt_inventory import load
    for item in load(root)['components'].values():
        if item.get('external')!='cpkt':continue
        parent=root/'.cache/deps'/target/item['directory']
        if parent.is_symlink():raise RuntimeError('component parent must not be a symlink')
        parent.mkdir(parents=True,exist_ok=True)
        link=parent/'install'
        if link.is_symlink():
            if link.resolve()!=prefix(root,target).resolve():raise RuntimeError('wrong imported core component link')
        elif link.exists():raise RuntimeError('owned producer output occupies imported core component: '+str(link))
        else:link.symlink_to(os.path.relpath(prefix(root,target),parent))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['ensure','validate','path','manifest'])
    parser.add_argument('--target',required=True)
    args=parser.parse_args();root=Path(__file__).resolve().parent.parent
    if args.action=='ensure':
        from cpkt_operation import run
        from cpkt_inventory import REPOSITORY_GROUP
        if 'CPKT_OPERATION_FD' not in os.environ:return run(root,REPOSITORY_GROUP,[sys.executable,__file__]+sys.argv[1:])
        print(acquire(root,args.target))
    elif args.action=='manifest':print(json.dumps(validate(root,args.target),sort_keys=True))
    else:
        validate(root,args.target)
        if args.action=='path':print(prefix(root,args.target))

if __name__=='__main__':
    try:sys.exit(main())
    except (RuntimeError,OSError,ValueError,KeyError,subprocess.CalledProcessError) as error:sys.exit('cpkt core prerequisite: '+str(error)+'\nPrepare: make deps-core PRESET=<target>-release')
