"""Observe native empty/player-only cargo delivery events in a disposable map.

Uses --create and a hidden normal --load-game client, never a source save or
desktop input. Does not import or change Production Flow. --prepare-only writes
an isolated test mod/config without starting Factorio.
"""
import argparse
from datetime import datetime
import hashlib,json,os
from pathlib import Path
import shutil,subprocess,time
from zipfile import ZipFile,ZIP_DEFLATED

ROOT=Path(__file__).resolve().parents[1]
PROFILE=Path(os.environ['APPDATA'])/'Factorio'
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def prepare(args):
    stage=ROOT/'tests/out'/datetime.now().strftime('cargo-empty-witness-%Y%m%d-%H%M%S-%f')
    mod=stage/'mods/cargo-empty-witness';mod.mkdir(parents=True)
    shutil.copyfile(ROOT/'tests/cargo_empty_witness.lua',mod/'control.lua')
    (mod/'cargo_empty_witness_config.lua').write_text('return { product_check='+('true' if args.product_check else 'false')+' }\n')
    (mod/'info.json').write_text(json.dumps({'name':'cargo-empty-witness','version':'0.0.1',
        'title':'Private Cargo Event Witness','author':'test','factorio_version':'2.1',
        'dependencies':['base >= 2.1','space-age']+(['production-flow'] if args.product_check else [])}))
    (stage/'mods/mod-list.json').write_text(json.dumps({'mods':[{'name':n,'enabled':True}
        for n in ('base','space-age','elevated-rails','quality','recycler','cargo-empty-witness')+
        (('production-flow',) if args.product_check else ())]}))
    (stage/'config.ini').write_text(f'[path]\nread-data={args.exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n'
        '[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\n[general]\nlocale=en\n')
    (stage/'map-gen.json').write_text(json.dumps({'width':256,'height':256,'seed':8,'peaceful_mode':True}))
    protected=[PROFILE/'config/config.ini',PROFILE/'mods/mod-list.json',PROFILE/'mods/mod-settings.dat',PROFILE/'player-data.json']
    manifest={'fixture':'new disposable map; native cargo events only; no Production Flow product code',
        'lua_sha256':digest(mod/'control.lua'),'protected_sha256':{str(p):digest(p) for p in protected if p.is_file()}}
    if args.product_check:
        target=stage/'mods/production-flow'
        shutil.copytree(ROOT/'mod/production-flow',target,ignore=shutil.ignore_patterns('tools'))
        manifest['fixture']='new disposable map; native cargo events and isolated current Production Flow with read-only remote observer'
        manifest['source_sha256']={p.relative_to(target).as_posix():digest(p) for p in target.rglob('*') if p.is_file()}
        info=json.loads((target/'info.json').read_text())
        package=stage/f"production-flow_{info['version']}-test-candidate.zip"
        with ZipFile(package,'w',ZIP_DEFLATED) as archive:
            for rel in sorted(manifest['source_sha256']):archive.write(target/rel,f"production-flow_{info['version']}/"+rel)
        manifest['candidate_sha256']=digest(package)
        control=target/'control.lua'
        with control.open('a',encoding='utf-8') as stream:
            stream.write('''
-- Private read-only event witness; excluded from the clean source archive.
remote.add_interface("cargo_empty_witness_product",{summary=function()
  local state=storage.transfers
  local result={sent=0,received=0,receipt_gaps=0,pending=state and state.pending_count or 0,received_iron_plate=0,
    pending_nonempty=0,pending_empty_unfinished=0,empty_delivered_markers=0}
  for _,pending in pairs(state and state.pending or {}) do
    if pending.empty and pending.empty_delivered_tick then result.empty_delivered_markers=result.empty_delivered_markers+1
    elseif pending.empty then result.pending_empty_unfinished=result.pending_empty_unfinished+1
    else result.pending_nonempty=result.pending_nonempty+1 end
  end
  local observations=state and state.boundary_observations
  for _,record in pairs(observations and observations.history or {}) do
    if record.kind=="sent" then result.sent=result.sent+1
    elseif record.kind=="received" then
      result.received=result.received+1
      result.received_iron_plate=result.received_iron_plate+(record.items and record.items["iron-plate"] or 0)
    elseif record.kind=="receipt-gap" then result.receipt_gaps=result.receipt_gaps+1 end
  end
  return result
end})
''')
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2))
    return stage,manifest
def run(stage,args):
    common=[str(args.exe),'--config',str(stage/'config.ini'),'--mod-directory',str(stage/'mods')]
    env=dict(os.environ,SteamAppId='427520',SteamGameId='427520')
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    with (stage/'create.log').open('w') as out:
        subprocess.run(common+['--create',str(stage/'fixture.zip'),'--map-gen-settings',str(stage/'map-gen.json')],
            stdout=out,stderr=subprocess.STDOUT,startupinfo=startup,env=env,check=True,timeout=120)
    log=stage/'native.log'
    with log.open('w') as out:
        process=subprocess.Popen(common+['--load-game',str(stage/'fixture.zip'),'--window-size','1280x720',
            '--disable-audio','--disable-migration-window','--force-graphics-preset','low'],
            stdout=out,stderr=subprocess.STDOUT,startupinfo=startup,env=env)
        try:
            deadline=time.monotonic()+args.timeout
            while time.monotonic()<deadline:
                text=log.read_text(encoding='utf-8',errors='replace')
                if 'CARGO EMPTY NATIVE WITNESS PASS' in text:
                    result=json.loads((stage/'script-output/cargo-empty/results.json').read_text())
                    if args.product_check:assert result['product_checks_passed'] and len(result['cases'])==2
                    else:assert result['player_only_native_transport_verified'] and len(result['cases'])==3
                    (stage/'evidence.json').write_text(json.dumps(result,indent=2));return result
                if process.poll() is not None or 'Error while' in text: raise RuntimeError(text[-6000:])
                time.sleep(.25)
            raise TimeoutError(f'Witness timed out; see {log}')
        finally:
            if process.poll() is None: process.terminate()
            process.wait(timeout=30)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe',type=Path,default=Path('D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe'))
    parser.add_argument('--prepare-only',action='store_true')
    parser.add_argument('--product-check',action='store_true',help='Witness actual current Production Flow receipts on cargo and empty pods; omit player-only setup')
    parser.add_argument('--timeout',type=int,default=180)
    args=parser.parse_args();stage,manifest=prepare(args)
    print(f'Witness stage: {stage}',flush=True)
    if args.prepare_only: return
    manifest['engine']=subprocess.check_output([str(args.exe),'--version'],text=True)
    (stage/'manifest.json').write_text(json.dumps(manifest,indent=2))
    try:
        result=run(stage,args)
        print(json.dumps(result,indent=2),flush=True)
    finally:
        changed=[p for p,h in manifest['protected_sha256'].items() if not Path(p).is_file() or digest(Path(p))!=h]
        (stage/'protected-check.json').write_text(json.dumps({'unchanged':not changed,'changed':changed},indent=2))
        if changed: raise RuntimeError(f'Protected profile files changed: {changed}')
if __name__=='__main__':main()
