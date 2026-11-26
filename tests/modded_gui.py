"""Warm and capture a user-authorized modded save in an isolated native client.

Supply a private mod folder already synchronized by Factorio's --sync-mods.
Never loads the original save, updates the live mod list or copies credentials.
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
from zipfile import BadZipFile, ZipFile, ZIP_DEFLATED

ROOT=Path(__file__).resolve().parents[1]
TESTS=ROOT/'tests'
PROFILE=Path(os.environ['APPDATA'])/'Factorio'
BUILTIN={'base','elevated-rails','quality','recycler','space-age'}

def digest(p):
    with p.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def prepare(args):
    rail=getattr(args,'cells_rail',False)
    prefix='cells-rail-se-' if rail else 'modded-gui-'
    stage=TESTS/'out'/(prefix+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    mods=stage/'mods';mods.mkdir(parents=True)
    config=json.loads((args.mods/'mod-list.json').read_text(encoding='utf-8-sig'))
    enabled={m['name']:m.get('version') for m in config['mods'] if m['enabled']}
    available={}
    for p in args.mods.iterdir():
        if p.suffix=='.zip':
            with ZipFile(p) as z:info=json.loads(z.read(next(n for n in z.namelist() if n.endswith('/info.json'))))
        elif p.is_dir() and (p/'info.json').is_file():info=json.loads((p/'info.json').read_text(encoding='utf-8-sig'))
        else:continue
        available[(info['name'],info['version'])]=p
    selected={}
    for name,version in enabled.items():
        if name in BUILTIN or name=='production-flow':continue
        if not version:
            options=[v for n,v in available if n==name]
            if not options:raise ValueError(f'Missing enabled mod: {name}')
            version=max(options,key=lambda v:tuple(map(int,v.split('.'))))
        p=available.get((name,version))
        if not p:raise ValueError(f'Missing enabled mod version: {name} {version}')
        if p.is_dir():shutil.copytree(p,mods/p.name)
        else:shutil.copy2(p,mods/p.name)
        selected[name]={'version':version,'source':str(p),'sha256':digest(p) if p.is_file() else None}
    source=ROOT/'mod/production-flow';target=mods/'production-flow'
    shutil.copytree(source,target,ignore=shutil.ignore_patterns('tools'))
    hashes={p.relative_to(source).as_posix():digest(p) for p in source.rglob('*') if p.is_file() and 'tools' not in p.relative_to(source).parts}
    info=json.loads((source/'info.json').read_text())
    package_name=f"{info['name']}_{info['version']}"
    package=stage/f'{package_name}.zip'
    with ZipFile(package,'w',ZIP_DEFLATED) as z:
        for name in sorted(hashes):z.write(source/name,package_name+'/'+name)
    shutil.copy2(args.save,stage/'input.zip')
    if (args.mods/'mod-settings.dat').is_file():shutil.copy2(args.mods/'mod-settings.dat',mods/'mod-settings.dat')
    enabled['production-flow']=info['version']
    entries=[{'name':name,'enabled':True,**({'version':version} if version else {})} for name,version in sorted(enabled.items())]
    for name in BUILTIN-set(enabled):entries.append({'name':name,'enabled':False})
    (mods/'mod-list.json').write_text(json.dumps({'mods':entries}))
    hooks=[('cells_rail_native.lua','modded_gui.lua')] if rail else [
        ('modded_gui.lua','modded_gui.lua'),('development/gui_interaction_checks.lua','gui_interaction_checks.lua')]
    for a,b in hooks:
        shutil.copyfile(TESTS/a,target/'scripts'/b)
    (target/'scripts/modded_gui_config.lua').write_text(
        f'return {{warm_seconds={args.warm_seconds},resolution={{{args.width},{args.height}}},'
        f' viewport={str(args.viewport).lower()},persist_warmed={str(not args.viewport).lower()}}}\n')
    if rail:
        # Verify the actual data-stage selection prototype, not only injected area events.
        with (target/'data-final-fixes.lua').open('a', encoding='utf-8') as data:
            data.write("""
local selection = require("shared.cell_selection")
local function has(values, wanted)
  for _, value in pairs(values) do if value == wanted then return true end end
end
for _, tool in ipairs({selection.tool, selection.stop_tool}) do
  local filters = assert(data.raw["selection-tool"][tool].select.entity_type_filters)
  for _, kind in ipairs({"train-stop", "container", "logistic-container", "storage-tank"}) do
    assert(has(filters, kind), tool .. " missing " .. kind)
  end
end
""")
    control=target/'control.lua';code=control.read_text(encoding='utf-8')
    needle='  Sampler.on_tick(e.tick)';assert code.count(needle)==1
    code='local ModdedGui=require("scripts.modded_gui")\n'+code.replace(needle,needle+'\n  ModdedGui.tick(UI,Sampler)')
    init='script.on_init(function() setup(true) end)';assert code.count(init)==1
    code=code.replace(init,'script.on_init(function() setup(true); ModdedGui.init() end)')
    code+='\nscript.on_nth_tick(1,ModdedGui.unpause)\n'
    control.write_text(code,encoding='utf-8')
    (stage/'config.ini').write_text(
        f'[path]\nread-data={args.exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n'
        '[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\nhide-achievement-popups=true\n'
        f'[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={args.scale}\n[general]\nlocale=en\n'
        '[sound]\nmaster-volume=0\nmaster-muted=true\n')
    protected=[args.save,PROFILE/'mods/mod-list.json',PROFILE/'mods/mod-settings.dat',PROFILE/'config/config.ini',PROFILE/'player-data.json']
    protected.extend(p for p in source.rglob('*') if p.is_file())
    manifest={'source_save':str(args.save),'source_save_sha256':digest(args.save),'input_sha256':digest(stage/'input.zip'),
        'engine':subprocess.check_output([str(args.exe),'--version'],text=True),'selected_mods':selected,
        'candidate_sha256':digest(package),'source_sha256':hashes,'configured_scale':args.scale,
        'resolution':[args.width,args.height],'warm_seconds':args.warm_seconds,
        'protected_sha256':{str(p):digest(p) for p in protected if p.is_file()},
        'test_sha256':{n:digest(TESTS/n) for n,_ in hooks}}
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2))
    return stage,manifest

def run(stage,manifest,args):
    rail=getattr(args,'cells_rail',False)
    command=[str(args.exe),'--config',str(stage/'config.ini'),'--mod-directory',str(stage/'mods'),
        '--load-game',str(stage/'input.zip'),'--window-size',f'{args.width}x{args.height}',
        '--disable-audio','--disable-migration-window','--force-graphics-preset','low']
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    log_path=stage/'native.log';print(f'Native modded stage: {stage}',flush=True)
    with log_path.open('w',encoding='utf-8') as stream:
        p=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT,startupinfo=startup,
            env=dict(os.environ,SteamAppId='427520',SteamGameId='427520'))
        (stage/'process.json').write_text(json.dumps({'pid':p.pid,'command':command},indent=2))
        try:
            deadline=time.monotonic()+args.timeout;last_progress=''
            while time.monotonic()<deadline:
                output=log_path.read_text(encoding='utf-8',errors='replace')
                progress=[line for line in output.splitlines() if 'MODDED GUI HISTORY' in line]
                if progress and progress[-1]!=last_progress:last_progress=progress[-1];print(last_progress,flush=True)
                if 'MODDED GUI NATIVE PASS' in output:
                    playtest=stage/'saves/_autosave-rail-playtest.zip'
                    if rail:
                        if not playtest.is_file():time.sleep(.5);continue
                        try:
                            with ZipFile(playtest) as saved:
                                if not saved.namelist():raise ValueError('Empty rail playtest save')
                        except (BadZipFile, OSError, ValueError, EOFError):
                            time.sleep(.5);continue
                    evidence=json.loads((stage/'script-output/modded-gui/results.json').read_text())
                    if rail:
                        expected={'rail-port-exclusions','rail-dedicated-ports','rail-suggestion-draft','rail-outlines-chart','rail-editor','cells-shared-edit','rail-overview','rail-stopped','rail-heading',
                            'rail-scheduled','rail-history-time','rail-history-events','cells-flow','cells-map',
                            'cells-layer-root','cells-layer-one','cells-layer-two',
                            'cells-layer-selected-root','cells-layer-selected-one'}
                        names=[case['name'] for case in evidence['cases']]
                        if len(names)!=len(expected) or set(names)!=expected:raise RuntimeError('Incomplete modded case matrix')
                    elif len(evidence['cases'])!=6:raise RuntimeError('Incomplete modded case matrix')
                    if evidence['display_scale']!=args.scale:raise RuntimeError('Unexpected actual native GUI scale')
                    shots={}
                    witnesses={}
                    for case in evidence['cases']:
                        shot=stage/'script-output/modded-gui'/f"{case['name']}.png"
                        if not shot.is_file() or shot.stat().st_size<10000:raise RuntimeError(f'Missing native screenshot: {shot}')
                        shots[shot.name]=digest(shot)
                        if case['renderer']=='poly' and (not args.viewport or case.get('camera')):
                            from PIL import Image
                            witness=stage/'script-output/modded-gui'/f"{case['name']}-camera-witness.png"
                            with Image.open(witness) as img:
                                count=sum(r>245 and g<10 and b>245 for r,g,b in img.convert('RGB').get_flattened_data())
                            if count<100:raise RuntimeError(f'Native camera failed visible-pixel witness: {witness} ({count} pixels)')
                            witnesses[witness.name]={'magenta_pixels':count,'sha256':digest(witness)}
                    evidence.update(candidate_sha256=manifest['candidate_sha256'],screenshots_sha256=shots)
                    if args.viewport:
                        if len(evidence.get('viewport', [])) != 5:raise RuntimeError('Incomplete Sankey viewport matrix')
                        for case in evidence['viewport']:
                            shot=stage/'script-output/modded-gui'/f"viewport-{case['name']}.png"
                            shots[shot.name]=digest(shot)
                    if rail:evidence['playtest_sha256']=digest(playtest)
                    evidence['camera_pixel_witnesses']=witnesses
                    (stage/'evidence.json').write_text(json.dumps(evidence,indent=2))
                    print(f'PASS real modded factory: {stage}',flush=True);return
                if p.poll() is not None or 'Error while' in output or 'Error ModManager' in output:
                    raise RuntimeError(output[-8000:])
                if (stage/'STOP').exists():raise RuntimeError('Stopped by stage owner')
                time.sleep(.5)
            raise TimeoutError(f'Modded native test exceeded {args.timeout}s: {stage}')
        finally:
            if p.poll() is None:p.terminate()
            p.wait(timeout=30)
            (stage/'process-stopped.json').write_text(json.dumps({'pid':p.pid,'returncode':p.returncode}))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--save',type=Path,required=True)
    parser.add_argument('--mods',type=Path,required=True)
    parser.add_argument('--exe',type=Path,default=Path('D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe'))
    parser.add_argument('--scale',type=float,default=1.25)
    parser.add_argument('--width',type=int,default=2560)
    parser.add_argument('--height',type=int,default=1440)
    parser.add_argument('--warm-seconds',type=int,default=600)
    parser.add_argument('--timeout',type=int,default=1200)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--cells-rail',action='store_true',help='Capture Cells rail UI and save an isolated playable copy')
    mode.add_argument('--viewport',action='store_true',help='Check Full Sankey viewport navigation on the warmed save')
    args=parser.parse_args();args.save=args.save.resolve();args.mods=args.mods.resolve()
    minimum=60 if args.cells_rail or args.viewport else 600
    if args.warm_seconds<minimum:raise ValueError(f'Collect at least {minimum} game seconds of real production history')
    stage,manifest=prepare(args)
    try:run(stage,manifest,args)
    finally:
        changed=[p for p,h in manifest['protected_sha256'].items() if not Path(p).is_file() or digest(Path(p))!=h]
        if digest(stage/'input.zip')!=manifest['input_sha256']:changed.append(str(stage/'input.zip'))
        (stage/'protected-check.json').write_text(json.dumps({'unchanged':not changed,'changed':changed},indent=2))
        if changed:raise RuntimeError(f'Original save/profile/source changed: {changed}')
        print('PASS original save, input copy, live profile and source hashes unchanged.',flush=True)

if __name__=='__main__':main()
