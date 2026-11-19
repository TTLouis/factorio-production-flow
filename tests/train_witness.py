import json, shutil, subprocess, hashlib, os
from pathlib import Path
from datetime import datetime
R=Path(__file__).resolve().parent.parent
E=Path('D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe')
S=R/'tests/out'/('train-witness-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
M=S/'mods/train-witness'; M.mkdir(parents=True)
shutil.copyfile(R/'tests/train_witness.lua',M/'control.lua')
(M/'info.json').write_text(json.dumps(dict(name='train-witness',version='0.0.1',title='Train witness',author='test',factorio_version='2.1',dependencies=['base >= 2.1'])))
(S/'mods/mod-list.json').write_text(json.dumps({'mods':[{'name':'base','enabled':True},{'name':'train-witness','enabled':True},*({'name':n,'enabled':False} for n in ('space-age','elevated-rails','quality','recycler'))]}))
(S/'config.ini').write_text(f'[path]\nread-data={E.parents[2].as_posix()}/data\nwrite-data={S.as_posix()}\n[sound]\nmaster-volume=0\nmaster-muted=true\n')
(S/'map-gen.json').write_text(json.dumps({'width':256,'height':256,'seed':42,'peaceful_mode':True}))
P=Path(os.environ['APPDATA'])/'Factorio'
protected=[P/'config/config.ini',P/'mods/mod-list.json',P/'mods/mod-settings.dat',P/'player-data.json']
digest=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={str(p):digest(p) for p in protected if p.is_file()}
manifest={'engine':subprocess.check_output([str(E),'--version'],text=True),'fixture_sha256':digest(M/'control.lua'),'protected':before}
(S/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Stage:',S,flush=True)
common=[str(E),'--config',str(S/'config.ini'),'--mod-directory',str(S/'mods'),'--disable-audio']
try:
 for name,args in [('create',['--create',str(S/'fixture.zip'),'--map-gen-settings',str(S/'map-gen.json')]),('benchmark',['--benchmark',str(S/'fixture.zip'),'--benchmark-ticks','1501','--benchmark-runs','1'])]:
  p=subprocess.run(common+args,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=180)
  (S/(name+'.log')).write_text(p.stdout+p.stderr,encoding='utf8')
  if p.returncode: raise RuntimeError((p.stdout+p.stderr)[-5000:])
  if name=='benchmark' and 'TRAIN WITNESS PASS' not in p.stdout+p.stderr: raise RuntimeError('No PASS marker; inspect benchmark.log')
finally:
 changed=[p for p,h in before.items() if not Path(p).is_file() or digest(Path(p))!=h]
 (S/'protected-check.json').write_text(json.dumps({'unchanged':not changed,'changed':changed},indent=2))
 if changed: raise RuntimeError('Profile changed: '+str(changed))
print('TRAIN WITNESS PASS')


