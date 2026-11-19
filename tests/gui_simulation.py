"""Actual engine mouse-input regression for chart rows, without OS input.

A private main-menu simulation loads the real mod runtime. A fixed-size chart
panel avoids virtual-player window-sizing differences: simulation players report
display_scale=1 even when the configured renderer GUI scale is 125% or 150%.
This verifies native hit testing and product event routing, not full-window layout.
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
                if not name.startswith('mod/production-flow/') or name.endswith('/'):continue
                path=target/Path(name).relative_to('mod/production-flow')
                path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(z.read(name))
    else:
        shutil.copytree(ROOT/'mod/production-flow',target,ignore=shutil.ignore_patterns('tools'))
    source={p.relative_to(target).as_posix():digest(p) for p in target.rglob('*') if p.is_file()}
    info=json.loads((target/'info.json').read_text(encoding='utf-8'))
    package_name=f"{info['name']}_{info['version']}"
    package=stage/f'{package_name}.zip'
    with ZipFile(package,'w',ZIP_DEFLATED) as z:
        for rel in sorted(source):z.write(target/rel,package_name+'/'+rel)
    shutil.copyfile(TESTS/'gui_simulation.lua',target/'scripts/gui_simulation.lua')
    control=target/'control.lua'
    control.write_text(control.read_text(encoding='utf-8')+
        '\nrequire("scripts.gui_simulation").install()\n',encoding='utf-8')
    # This definition belongs only to the isolated test copy and clean archives
    # above are created before any runtime/data-stage instrumentation is added.
    with (target/'data-final-fixes.lua').open('a',encoding='utf-8') as stream:
        stream.write('''
data.raw["utility-constants"].default.main_menu_simulations={
 gui_input={generate_map=true,checkboard=false,length=36000,mods={"production-flow"},
 init=[[local p=game.simulation.create_test_player{name="gui-input"};game.simulation.camera_player=p;
 game.simulation.camera_position={0,0};game.simulation.camera_zoom=1;game.simulation.camera_player_cursor_position={0,0};
 remote.call("production-flow-gui-simulation","start",p.index)]],
 update=[[local ok,err=pcall(remote.call,"production-flow-gui-simulation","tick");
 if not ok then log("GUI SIMULATION FAILURE "..tostring(err)) end]]}}
''')
    (stage/'mods/mod-list.json').write_text(json.dumps({'mods':[
        {'name':n,'enabled':n in ('base','production-flow')}
        for n in ('base','production-flow','space-age','elevated-rails','quality','recycler')]}))
    (stage/'config.ini').write_text(
        f'[path]\nread-data={args.exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n'
        '[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\nhide-achievement-popups=true\n'
        f'[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={scale}\n[general]\nlocale=en\n')
    manifest={'source_ref':args.source_ref,'engine':subprocess.check_output([str(args.exe),'--version'],text=True),
        'source_sha256':source,'candidate_sha256':digest(package),'configured_scale':scale,
        'test_sha256':{'gui_simulation.lua':digest(TESTS/'gui_simulation.lua'),
                      'gui_simulation.py':digest(TESTS/'gui_simulation.py')},
        'input_method':'Engine-native LuaSimulation cursor/mouse events; no OS input or direct handlers',
        'scale_note':'Virtual player reports1; fixed chart geometry is rendered at configured GUI scale.'}
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2))
    return manifest


def run(stage,args):
    command=[str(args.exe),'--config',str(stage/'config.ini'),'--mod-directory',str(stage/'mods'),
        '--window-size','1920x1080','--disable-audio','--disable-migration-window','--force-graphics-preset','low']
    environment=dict(os.environ,SteamAppId='427520',SteamGameId='427520')
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    log_path=stage/'native.log'
    with log_path.open('w',encoding='utf-8') as output:
        process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,env=environment,startupinfo=startup)
        (stage/'process.json').write_text(json.dumps({'pid':process.pid,'command':command},indent=2))
        try:
            deadline=time.monotonic()+args.timeout
            while time.monotonic()<deadline:
                log=log_path.read_text(encoding='utf-8',errors='replace')
                if 'GUI SIMULATION NATIVE PASS' in log:
                    result=json.loads((stage/'script-output/gui-simulation/results.json').read_text(encoding='utf-8'))
                    if len(result['cases'])!=18:raise RuntimeError('Incomplete engine-input case matrix')
                    manifest=json.loads((stage/'manifest.json').read_text())
                    result['configured_scale']=manifest['configured_scale']
                    result['candidate_sha256']=manifest['candidate_sha256']
                    result['native_log_sha256']=digest(log_path)
                    (stage/'evidence.json').write_text(json.dumps(result,indent=2))
                    print(f'PASS 18 actual chart clicks at configured {result["configured_scale"]:.0%}: {stage}',flush=True)
                    return
                if process.poll() is not None or 'Error while' in log or 'Error ModManager' in log or 'GUI SIMULATION FAILURE' in log:
                    raise RuntimeError(log[-7000:])
                if (stage.parent/'STOP').exists():raise RuntimeError('Native simulation stopped by its owner')
                time.sleep(.2)
            raise TimeoutError(f'Native simulation exceeded {args.timeout}s: {stage}')
        finally:
            if process.poll() is None:process.terminate()
            process.wait(timeout=30)
            (stage/'process-stopped.json').write_text(json.dumps({'pid':process.pid,'returncode':process.returncode}))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe',type=Path,default=Path('D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe'))
    parser.add_argument('--scales',type=float,nargs='+',default=[1,1.25,1.5])
    parser.add_argument('--source-ref',help='Immutable local Git ref; preserves the current checkout')
    parser.add_argument('--timeout',type=int,default=180)
    args=parser.parse_args()
    root=TESTS/'out'/datetime.now().strftime('gui-simulation-%Y%m%d-%H%M%S-%f');root.mkdir(parents=True)
    paths=[PROFILE/'mods/mod-list.json',PROFILE/'mods/mod-settings.dat',PROFILE/'config/config.ini',PROFILE/'player-data.json']
    paths.extend(p for p in (ROOT/'mod/production-flow').rglob('*') if p.is_file())
    original={str(p):digest(p) for p in paths if p.is_file()}
    (root/'protected-sha256.json').write_text(json.dumps(original,indent=2))
    print(f'Evidence: {root}',flush=True)
    try:
        for index,scale in enumerate(args.scales):
            if not .5<=scale<=2:raise ValueError('GUI scale must be between 0.5 and 2')
            stage=root/f'{index}-{scale:g}'
            prepare(stage,args,scale);run(stage,args)
    finally:
        changed=[p for p,h in original.items() if not Path(p).is_file() or digest(Path(p))!=h]
        (root/'protected-check.json').write_text(json.dumps({'unchanged':not changed,'changed':changed},indent=2))
        if changed:raise RuntimeError(f'Original profile changed: {changed}')
        print('PASS original profile and source hashes unchanged; no source saves loaded.',flush=True)


if __name__=='__main__':main()
