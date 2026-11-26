"""Native chart geometry/event-contract regression, using launch arguments only.

Uses a new vanilla map and synthetic rates derived from vanilla recipes. Checks
actual native GUI properties plus a canvas-coordinate hit model; direct handler
checks are reported separately. Does not send desktop input or load user saves.
"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from zipfile import ZipFile, ZIP_DEFLATED

ROOT=Path(__file__).resolve().parents[1]
TESTS=ROOT/'tests'
PROFILE=Path(os.environ['APPDATA'])/'Factorio'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()

def prepare(stage,args,scale):
    stage.mkdir()
    target=stage/'mods/production-flow'
    if args.source_ref:
        archive=stage/'source-ref.zip'
        with archive.open('wb') as stream:
            subprocess.run(['git','-c',f'safe.directory={ROOT.as_posix()}','archive','--format=zip',
                args.source_ref,'mod/production-flow'],cwd=ROOT,stdout=stream,check=True)
        with ZipFile(archive) as z:
            for name in z.namelist():
                if not name.startswith('mod/production-flow/') or name.endswith('/'): continue
                path=target/Path(name).relative_to('mod/production-flow')
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(z.read(name))
    else:
        shutil.copytree(ROOT/'mod/production-flow',target,ignore=shutil.ignore_patterns('tools'))
    sources={p.relative_to(target).as_posix():digest(p) for p in target.rglob('*') if p.is_file()}
    info=json.loads((target/'info.json').read_text())
    package_name=f"{info['name']}_{info['version']}"
    package=stage/f'{package_name}.zip'
    with ZipFile(package,'w',ZIP_DEFLATED) as z:
        for rel in sorted(sources): z.write(target/rel,package_name+'/'+rel)
    manifest={'source_ref':args.source_ref,'engine':subprocess.check_output([str(args.exe),'--version'],text=True),
        'source_sha256':sources,'candidate_sha256':digest(package),'scale':scale,
        'expect_obstruction':args.expect_obstruction,'fixture':'vanilla synthetic recipe rates; new disposable map',
        'checks':'native properties and modeled canvas hit regions; handler dispatch is not engine mouse input'}
    helpers={'gui_interaction.lua':'gui_interaction.lua','development/gui_interaction_checks.lua':'gui_interaction_checks.lua'}
    if args.ribbon_checks:
        helpers['development/gui_ribbon_checks.lua']='gui_ribbon_checks.lua'
    manifest['test_sha256']={name:digest(TESTS/name) for name in helpers}
    for name,out in helpers.items(): shutil.copyfile(TESTS/name,target/'scripts'/out)
    (target/'scripts/gui_interaction_mode.lua').write_text(
        f'return {{broken={str(args.expect_obstruction).lower()}, ribbons={str(args.ribbon_checks).lower()}}}\n')
    control=target/'control.lua'
    source=control.read_text(encoding='utf-8')
    needle='  Sampler.on_tick(e.tick)'
    assert source.count(needle)==1
    source='local GuiInteraction = require("scripts.gui_interaction")\n'+source.replace(needle,needle+'\n  GuiInteraction.tick(UI)')
    init='script.on_init(function() setup(true) end)'
    assert source.count(init)==1
    source=source.replace(init,'script.on_init(function() setup(true); GuiInteraction.init() end)')
    control.write_text(source,encoding='utf-8')
    (stage/'mods/mod-list.json').write_text(json.dumps({'mods':[
        {'name':n,'enabled':n in ('base','production-flow')}
        for n in ('base','production-flow','space-age','elevated-rails','quality','recycler')]}))
    (stage/'config.ini').write_text(
        f'[path]\nread-data={args.exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n'
        '[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\nhide-achievement-popups=true\n'
        f'[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={scale}\nshow-tips-and-tricks-notifications=false\n'
        '[general]\nlocale=en\n'
        '[sound]\nmaster-volume=0\nmaster-muted=true\n')
    (stage/'map-gen.json').write_text(json.dumps({'width':64,'height':64,'seed':3,'peaceful_mode':True}))
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2))
    return manifest

def ribbon_pixels(path, checks, scale, required=('straight','curve','elbow')):
    from PIL import Image

    def distance(a, b):
        return max(abs(x-y) for x,y in zip(a,b))

    with Image.open(path) as screenshot:
        img=screenshot.convert('RGB')
    pixels=img.load()
    first,second=checks['marker']
    size=int(4*scale)
    # The paired solid swatches mark (0, 0) in the same GUI coordinate space as the ribbons.
    origins=[]
    for y in range(img.height//2):
        for x in range(0,img.width-2*size):
            if (distance(pixels[x,y],first)<=5 and distance(pixels[x+size,y],second)<=5
                and (not x or distance(pixels[x-1,y],first)>5)
                and (not y or distance(pixels[x,y-1],first)>5)):
                origins.append((x,y))
    if len(origins)!=1: raise RuntimeError(f'Expected one chart origin in {path.name}, found {origins}')
    ox,oy=origins[0]
    background=pixels[ox+size*3,oy+size*2]
    # Use the empty strip below the tier labels to find the start of the scrollbar.
    # The screenshot can include a scrollable chart wider than its viewport.
    right=next((x for x in range(ox+size*3,img.width)
                if distance(pixels[x,oy+int(32*scale)],background)>8),img.width)
    bottom=next((y for y in range(oy+size*2,img.height)
                 if distance(pixels[ox+size*3,y],background)>8),img.height)
    observed={}
    solid_colors={}
    for probe in checks['probes']:
        edge,center=int(probe['edge']*scale),int(probe['center']*scale)
        across=lambda offset: (ox+edge+offset,oy+center) if probe['axis']=='x' else (ox+center,oy+edge+offset)
        sample=[across(i) for i in range(-3,4)]
        if not all(ox<=x<right and oy<=y<bottom for x,y in sample): continue
        colors=[pixels[xy] for xy in sample]
        if min(distance(colors[0],background),distance(colors[-1],background))<22: continue
        if probe['kind']!='node' and distance(colors[0],colors[-1])>12: continue
        if any(distance(color,background)<6 for color in colors[2:5]):
            raise RuntimeError(f'Background breaks {probe["kind"]} ribbon join in {path.name}: {sample} {colors}')
        if probe['kind']=='straight' and colors[0]==colors[-1]:
            if colors[2:5]!=[colors[0]]*3:
                raise RuntimeError(f'Visible straight join in {path.name}: {sample} {colors}')
            solid_colors[(probe['axis'],edge,center)]=colors[0]
        observed[probe['kind']]=observed.get(probe['kind'],0)+1
    if not all(observed.get(kind,0)>0 for kind in required):
        raise RuntimeError(f'Missing visible join coverage in {path.name}: {observed}')
    return observed,solid_colors


def run(stage,args):
    common=[str(args.exe),'--config',str(stage/'config.ini'),'--mod-directory',str(stage/'mods')]
    env=dict(os.environ,SteamAppId='427520',SteamGameId='427520')
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    with (stage/'create.log').open('w') as stream:
        subprocess.run(common+['--create',str(stage/'fixture.zip'),'--map-gen-settings',str(stage/'map-gen.json')],
            stdout=stream,stderr=subprocess.STDOUT,env=env,startupinfo=startup,check=True,timeout=120)
    command=common+['--load-game',str(stage/'fixture.zip'),'--window-size','1920x1080',
        '--disable-audio','--disable-migration-window','--force-graphics-preset','low']
    log_path=stage/'native.log'
    with log_path.open('w') as stream:
        process=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT,env=env,startupinfo=startup)
        try:
            deadline=time.monotonic()+args.timeout
            while time.monotonic()<deadline:
                output=log_path.read_text(encoding='utf-8',errors='replace')
                if 'GUI INTERACTION NATIVE PASS' in output:
                    results=json.loads((stage/'script-output/gui-interaction/results.json').read_text())
                    if len(results['cases'])!=6+args.ribbon_checks: raise RuntimeError('Incomplete native case matrix')
                    if results['scale']!=json.loads((stage/'manifest.json').read_text())['scale']:
                        raise RuntimeError('Unexpected native GUI scale')
                    captures,colors={},{}
                    for case in results['cases']:
                        image=stage/'script-output/gui-interaction'/f"{case['name']}.png"
                        if not image.is_file() or image.stat().st_size<10000: raise RuntimeError(f'Missing native screenshot {image}')
                        captures[image.name]=digest(image)
                        if 'fit_capture' in case:
                            fitted=image.with_name(case['fit_capture'])
                            if not fitted.is_file() or fitted.stat().st_size<10000: raise RuntimeError(f'Missing native screenshot {fitted}')
                            captures[fitted.name]=digest(fitted)
                            if 'fit_join' in case:
                                case['fit_pixels_checked'],_=ribbon_pixels(fitted,case['fit_join'],results['scale'],('node',))
                        for name in ('producer_capture', 'machine_capture'):
                            if name in case:
                                shot=image.with_name(case[name])
                                if not shot.is_file() or shot.stat().st_size<10000: raise RuntimeError(f'Missing native screenshot {shot}')
                                captures[shot.name]=digest(shot)
                        if case.get('sidebar_made_by') and 'machine_capture' not in case:
                            raise RuntimeError('Missing Full Sankey machine inspection')
                        if 'ribbon_checks' in case:
                            count,samples=ribbon_pixels(image,case['ribbon_checks'],results['scale'])
                            case['ribbon_pixels_checked']=count
                            colors[case['name']]=samples
                    if args.ribbon_checks:
                        normal=colors['sankey-sprites']
                        equipped=colors['sankey-night-vision']
                        shared=normal.keys() & equipped.keys()
                        if not shared or any(normal[key]!=equipped[key] for key in shared):
                            raise RuntimeError('Night vision changed the colour of a matched sprite ribbon')
                        results['night_vision_ribbon_colors_matched']=len(shared)
                    for filename in results.get('viewport_modes', {}).values():
                        captures[filename]=digest(stage/'script-output/gui-interaction'/filename)
                    for filename in results.get('rate_card', {}).values():
                        card=stage/'script-output/gui-interaction'/filename
                        if not card.is_file() or card.stat().st_size<10000:
                            raise RuntimeError(f'Missing Full Sankey rate-card screenshot {card}')
                        captures[filename]=digest(card)
                    results['screenshots_sha256']=captures
                    (stage/'evidence.json').write_text(json.dumps(results,indent=2))
                    print(f'PASS native contracts at {results["scale"]:.0%}: {stage}',flush=True)
                    return
                if process.poll() is not None or 'Error while' in output:
                    raise RuntimeError(output[-6000:])
                time.sleep(.2)
            raise TimeoutError(f'Native GUI test timed out: {stage}')
        finally:
            if process.poll() is None: process.terminate()
            process.wait(timeout=30)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe',type=Path,default=Path('D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe'))
    parser.add_argument('--scales',type=float,nargs='+',default=[1,1.25,1.5])
    parser.add_argument('--source-ref',help='Test an immutable local Git ref without changing the checkout')
    parser.add_argument('--expect-obstruction',action='store_true',help='Require the historical wrapper obstruction to reproduce')
    parser.add_argument('--ribbon-checks',action='store_true',help='Measure native ribbon joins and verify powered night vision')
    parser.add_argument('--timeout',type=int,default=120)
    args=parser.parse_args()
    root=TESTS/'out'/datetime.now().strftime('gui-interaction-%Y%m%d-%H%M%S-%f');root.mkdir(parents=True)
    protected=[p for p in PROFILE.rglob('*') if p.is_file() and (p.parent.name in ('saves','mods','config') or p.name=='player-data.json')]
    protected += [p for p in (ROOT/'mod/production-flow').rglob('*') if p.is_file()]
    originals={str(p):digest(p) for p in protected}
    (root/'protected-sha256.json').write_text(json.dumps(originals,indent=2))
    try:
        for index,scale in enumerate(args.scales):
            stage=root/f'{index}-{scale:g}'
            prepare(stage,args,scale);run(stage,args)
    finally:
        changed=[p for p,h in originals.items() if not Path(p).is_file() or digest(Path(p))!=h]
        (root/'protected-check.json').write_text(json.dumps({'unchanged':not changed,'changed':changed},indent=2))
        if changed: raise RuntimeError(f'Protected profile/source files changed: {changed}')
        print(f'PASS original profile and source hashes unchanged. Evidence: {root}',flush=True)

if __name__=='__main__': main()
