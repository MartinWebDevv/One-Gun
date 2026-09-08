from pathlib import Path
import os,shutil,subprocess,json,struct,time,io
from PIL import Image
root=Path.cwd();out=root/'artifacts/quality_pass_20260907'
cli=Path(os.environ['LOCALAPPDATA'])/'npm-cache/_npx/a6797f7ff67bb1f2/node_modules/@gltf-transform/cli/bin/cli.js'
def read(path):
    b=path.read_bytes();size=struct.unpack_from('<I',b,12)[0];return json.loads(b[20:20+size])
def resize_glb(src,dest):
    raw=src.read_bytes();n=struct.unpack_from('<I',raw,12)[0];j=json.loads(raw[20:20+n]);start=20+n;binary=raw[start+8:]
    replacements={}
    for image in j.get('images',[]):
        if 'bufferView' not in image: continue
        idx=image['bufferView'];v=j['bufferViews'][idx];a=v.get('byteOffset',0)
        im=Image.open(io.BytesIO(binary[a:a+v['byteLength']]))
        if max(im.size)<=1024:continue
        im.thumbnail((1024,1024),Image.Resampling.LANCZOS)
        b=io.BytesIO();im.save(b,format='PNG');replacements[idx]=b.getvalue();image['mimeType']='image/png'
    rebuilt=bytearray()
    for idx,v in enumerate(j['bufferViews']):
        assert v.get('buffer',0)==0
        a=v.get('byteOffset',0);data=replacements.get(idx,binary[a:a+v['byteLength']])
        rebuilt.extend(b'\0'*((-len(rebuilt))%4));v['byteOffset']=len(rebuilt);v['byteLength']=len(data);rebuilt.extend(data)
    j['buffers'][0]['byteLength']=len(rebuilt);rebuilt.extend(b'\0'*((-len(rebuilt))%4))
    meta=json.dumps(j,separators=(',',':')).encode();meta+=b' '*((-len(meta))%4)
    dest.write_bytes(struct.pack('<III',0x46546c67,2,28+len(meta)+len(rebuilt))+struct.pack('<II',len(meta),0x4e4f534a)+meta+struct.pack('<II',len(rebuilt),0x004e4942)+rebuilt)
def metadata(j):
    return {'triangles':sum(j['accessors'][p['indices']]['count']//3 for m in j.get('meshes',[]) for p in m['primitives'] if 'indices' in p),'nodes':len(j.get('nodes',[])),'skins':len(j.get('skins',[])),'animations':len(j.get('animations',[]))}
results=[]
for label,rel,ratio in [('bot','models/new guy one gun model orange running.glb','0.12'),('bat','models/weaponModels/baseball_bat.glb','0.15')]:
    src=root/rel;backup=out/'backups'/rel;backup.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,backup)
    welded=out/(label+'_welded.glb');simple=out/(label+'_simplified.glb');final=out/(label+'_optimized.glb')
    with (out/(label+'_optimization.log')).open('w') as log:
        for args in [['weld',str(src),str(welded)],['simplify',str(welded),str(simple),'--ratio',ratio,'--error','0.001']]:
            subprocess.run(['node',str(cli),*args],check=True,stdout=log,stderr=subprocess.STDOUT,timeout=120)
    resize_glb(simple,final)
    a=read(src);b=read(final)
    assert [(n.get('name'),n.get('children'),n.get('skin')) for n in a.get('nodes',[])]==[(n.get('name'),n.get('children'),n.get('skin')) for n in b.get('nodes',[])]
    assert [s['joints'] for s in a.get('skins',[])]==[s['joints'] for s in b.get('skins',[])]
    assert len(a.get('animations',[]))==len(b.get('animations',[]))
    r={'asset':rel,'before':metadata(a),'after':metadata(b),'before_bytes':src.stat().st_size,'after_bytes':final.stat().st_size};results.append(r);print(json.dumps(r),flush=True)
(out/'asset_optimization.json').write_text(json.dumps(results,indent=2))
