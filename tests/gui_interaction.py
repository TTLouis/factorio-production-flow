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
    manifest['test_sha256']={name:digest(TESTS/name) for name in helpers}
    for name,out in helpers.items(): shutil.copyfile(TESTS/name,target/'scripts'/out)
    (target/'scripts/gui_interaction_mode.lua').write_text('return '+('true' if args.expect_obstruction else 'false')+'\n')
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
        f'[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={scale}\n[general]\nlocale=en\n'
        '[sound]\nmaster-volume=0\nmaster-muted=true\n')
    (stage/'map-gen.json').write_text(json.dumps({'width':64,'height':64,'seed':3,'peaceful_mode':True}))
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2))
    return manifest

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
                    if len(results['cases'])!=6: raise RuntimeError('Incomplete native case matrix')
                    if results['scale']!=json.loads((stage/'manifest.json').read_text())['scale']:
                        raise RuntimeError('Unexpected native GUI scale')
                    captures={}
                    for case in results['cases']:
                        image=stage/'script-output/gui-interaction'/f"{case['name']}.png"
                        if not image.is_file() or image.stat().st_size<10000: raise RuntimeError(f'Missing native screenshot {image}')
                        captures[image.name]=digest(image)
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
