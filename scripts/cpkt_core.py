#!/usr/bin/env python3
"""Validate pinned published core SDK identities and safe archive extraction."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import sys


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


def main():
    parser=argparse.ArgumentParser(description='Validate pinned core SDK structure; Bash/CMake own acquisition')
    parser.add_argument('action',choices=['pin','validate','path','manifest','extract','extracted-path'])
    parser.add_argument('--target',required=True)
    parser.add_argument('--archive',type=Path)
    parser.add_argument('--destination',type=Path)
    args=parser.parse_args();root=Path(__file__).resolve().parent.parent
    if args.action=='pin':
        print(json.dumps(pin(root,args.target),sort_keys=True))
    elif args.action in ('extract','extracted-path'):
        item=pin(root,args.target)
        if not args.destination:parser.error('extraction destination is required')
        name='cpkt-'+item['version']+'-'+args.target
        if args.action=='extracted-path':
            print(args.destination/name)
            return
        from cpkt_lock import delegated
        from cpkt_inventory import REPOSITORY_GROUP
        delegated(root,REPOSITORY_GROUP)
        if not args.archive or validator(root).sha(args.archive)!=item['sha256']:
            raise RuntimeError('pinned core archive checksum mismatch')
        from cpkt_packages import safe_extract
        extracted=safe_extract(args.archive,args.destination,name)
        validator(root).validate(extracted,['core'],item['version'],args.target,{'core':item['package_id']})
    elif args.action=='manifest':
        print(json.dumps(validate(root,args.target),sort_keys=True))
    else:
        validate(root,args.target)
        if args.action=='path':print(prefix(root,args.target))

if __name__=='__main__':
    try:sys.exit(main())
    except (RuntimeError,OSError,ValueError,KeyError) as error:sys.exit('cpkt core prerequisite: '+str(error)+'\nPrepare: make deps-core PRESET=<target>-release')
