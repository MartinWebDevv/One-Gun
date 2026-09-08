from pathlib import Path
import json, struct, subprocess, re, io, collections
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]; OUT=Path(__file__).resolve().parent
files=[ROOT/p for p in subprocess.check_output(['rg','--files','--hidden','-g','!.git/**','-g','!.godot/**','-g','!artifacts/**','-g','!build/**','-g','!services/**','-g','!art_src/**'],cwd=ROOT,text=True).splitlines()]
refs=collections.defaultdict(list); missing=[]
for p in files:
    if p.suffix.lower() not in ('.gd','.tscn','.tres','.godot','.gdshader'):continue
    try: source=p.read_text(encoding='utf-8-sig')
    except: continue
    for i,line in enumerate(source.splitlines(),1):
        for ref in re.findall(r'[\"\']res://([^\"\'\n]+)[\"\']',line):
            refs[ref].append(f'{p.relative_to(ROOT).as_posix()}:{i}')
            if not (ROOT/ref).exists() and not any(c in ref for c in ('%','*','{')):
                missing.append({'path':ref,'source':f'{p.relative_to(ROOT).as_posix()}:{i}'})
models=[]; images=[]; failures=[]
for p in files:
    rel=p.relative_to(ROOT).as_posix()
    if p.suffix.lower()=='.glb':
        try:
            data=p.read_bytes(); size,kind=struct.unpack_from('<II',data,12); g=json.loads(data[20:20+size]); acc=g.get('accessors',[])
            triangles=0
            for mesh in g.get('meshes',[]):
                for prim in mesh.get('primitives',[]):
                    n=acc[prim['indices']]['count'] if 'indices' in prim else acc[prim['attributes']['POSITION']]['count']
                    mode=prim.get('mode',4); triangles+=n//3 if mode==4 else max(0,n-2) if mode in (5,6) else 0
            dims=[]; binstart=20+size+8
            for img in g.get('images',[]):
                if 'bufferView' in img:
                    v=g['bufferViews'][img['bufferView']]; start=binstart+v.get('byteOffset',0)
                    with Image.open(io.BytesIO(data[start:start+v['byteLength']])) as im: dims.append(list(im.size))
            models.append(dict(path=rel,bytes=len(data),triangles=triangles,meshes=len(g.get('meshes',[])),materials=len(g.get('materials',[])),animations=len(g.get('animations',[])),textures=dims,references=refs.get(rel,[])))
        except Exception as e: failures.append(dict(path=rel,error=str(e)))
    elif p.suffix.lower() in ('.png','.jpg','.jpeg','.webp','.tga','.bmp'):
        try:
            with Image.open(p) as im: w,h=im.size
            images.append(dict(path=rel,bytes=p.stat().st_size,width=w,height=h,references=refs.get(rel,[])))
        except Exception as e: failures.append(dict(path=rel,error=str(e)))
models.sort(key=lambda x:x['bytes'],reverse=True)
images.sort(key=lambda x:x['width']*x['height'],reverse=True)
summary=dict(files=len(files),extensions=dict(collections.Counter(p.suffix.lower() for p in files)),models=models,images=images,missing_literal_resources=missing,failures=failures)
(OUT/'asset_inventory.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(dict(files=len(files),glb_count=len(models),glb_total_mb=round(sum(x['bytes'] for x in models)/1048576,1),image_count=len(images),glbs_over_10mb=sum(x['bytes']>10*1048576 for x in models),models_over_100k_tris=sum(x['triangles']>100000 for x in models),images_4k_plus=sum(max(x['width'],x['height'])>=4096 for x in images),invalid_assets=failures,largest_models=models[:18],largest_images=images[:12],missing_literal_resources=missing[:55]),indent=2))
