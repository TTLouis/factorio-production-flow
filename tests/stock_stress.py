"""Repeatable chest-map construction and paired native-engine UPS benchmarks.

Uses an isolated profile, never the live Factorio profile. Benchmark fixtures use
fixed-seed full inventories and verify every item total before saving. Baselines
disable only the new per-tick stock sampler; all other mod code remains enabled.
"""
import argparse
import csv
from datetime import datetime
import hashlib
import json
import msvcrt
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
EXE=Path(r'D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe')
SOURCE=ROOT/'mod/production-flow'


def install(stage,mode,count=0,baseline=False,opened=False):
    target=stage/'mods/production-flow'
    shutil.copytree(SOURCE,target,dirs_exist_ok=True,ignore=shutil.ignore_patterns('tools'))
    shutil.copyfile(ROOT/'tests/stock_stress.lua',target/'scripts/stock_stress.lua')
    (target/'scripts/stock_stress_config.lua').write_text(
        f'return {{mode="{mode}",count={count},open={str(opened).lower()}}}\n')
    control=(target/'control.lua').read_text()
    needle='  Sampler.on_tick(e.tick)'
    assert control.count(needle)==1
    (target/'control.lua').write_text('local StockTest=require("scripts.stock_stress")\n'+control.replace(
        needle,needle+'\n  StockTest.tick(UI,Sampler)'))
    if baseline:
        p=target/'scripts/sampler.lua'
        p.write_text(p.read_text().replace('  ChestStock.tick(tick)','  -- Stock sampling disabled in benchmark baseline only.'))


def execute(stage,args,label,marker=None,timeout=600):
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    logfile=stage/f'{label}.log'
    command=[str(EXE),'--config',str(stage/'config.ini'),'--mod-directory',str(stage/'mods'),*map(str,args)]
    with logfile.open('w',encoding='utf-8') as output:
        p=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,startupinfo=startup,
                           env=dict(os.environ,SteamAppId='427520',SteamGameId='427520'))
        deadline=time.monotonic()+timeout
        try:
            while p.poll() is None:
                text=logfile.read_text(encoding='utf-8',errors='replace')
                if marker and marker in text and 'Saving finished' in text:return text
                if 'Error while' in text or 'Error ModManager' in text:raise RuntimeError(text[-5000:])
                if time.monotonic()>deadline:raise TimeoutError(str(logfile))
                time.sleep(1)
            text=logfile.read_text(encoding='utf-8',errors='replace')
            if p.returncode or (marker and marker not in text):raise RuntimeError(text[-5000:])
            return text
        finally:
            if p.poll() is None:p.terminate()
            p.wait(timeout=30)


def prepare():
    stage=ROOT/'tests/out'/datetime.now().strftime('stock-stress-%Y%m%d-%H%M%S')
    (stage/'mods').mkdir(parents=True)
    (stage/'mods/mod-list.json').write_text(json.dumps({'mods':[{'name':n,'enabled':True} for n in
        ['base','elevated-rails','quality','space-age','recycler','production-flow']]}))
    (stage/'config.ini').write_text(f'[path]\nread-data={EXE.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n'
        '[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\nhide-achievement-popups=true\n')
    (stage/'map-gen.json').write_text(json.dumps({'seed':20261024,'width':64,'height':64,
        'autoplace_controls':{},'default_enable_all_autoplace_controls':False}))
    install(stage,'seed')
    execute(stage,['--create',stage/'seed.zip','--map-gen-settings',stage/'map-gen.json'],'create')
    return stage


def benchmark(stage,save,label,ticks,runs,baseline,opened):
    install(stage,'benchmark',baseline=baseline,opened=opened)
    print(f'Benchmark {label}: baseline={baseline}, open={opened}',flush=True)
    text=execute(stage,['--benchmark',save,'--benchmark-ticks',ticks,'--benchmark-runs',runs,
                        '--benchmark-verbose','all'],label,timeout=1200)
    results=re.findall(r'avg: ([\d.]+) ms, min: ([\d.]+) ms, max: ([\d.]+) ms',text)
    if not results:raise RuntimeError('Unrecognized benchmark output: '+text[-2000:])
    # Verbose values are engine nanoseconds. Drop the first 300 ticks of each run
    # so opening a GUI and initial caches do not dominate steady-state percentiles.
    columns=None; samples=[]
    for line in text.splitlines():
        if line.startswith('tick,'):columns=next(csv.reader([line]))
        elif columns and re.match(r'^t\d+,',line):
            row=next(csv.reader([line]));tick=int(row[0][1:])
            if tick>=300:samples.append({name:float(row[columns.index(name)])/1e6
                for name in ['wholeUpdate','scriptUpdate']})
    metrics={}
    for name in ['wholeUpdate','scriptUpdate']:
        values=sorted(s[name] for s in samples)
        if values:metrics[name]={'mean_ms':statistics.mean(values),'p95_ms':values[int((len(values)-1)*.95)],
                                'p99_ms':values[int((len(values)-1)*.99)],'max_ms':max(values),'samples':len(values)}
    return {'steady_state':metrics,'save':str(save),'sha256':hashlib.sha256(save.read_bytes()).hexdigest(),
            'baseline':baseline,'open':opened,'ticks':ticks,'runs':runs,
            'engine_results':[dict(zip(['avg_ms','min_ms','max_ms'],map(float,row))) for row in results],
            'log':str(stage/f'{label}.log')}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage',type=Path);p.add_argument('--counts',type=int,nargs='+',default=[1000,10000,50000])
    p.add_argument('--ticks',type=int,default=3600);p.add_argument('--runs',type=int,default=3)
    p.add_argument('--settings-check',action='store_true')
    p.add_argument('--capture',action='store_true');p.add_argument('--build-only',action='store_true');p.add_argument('--benchmark-only',action='store_true')
    p.add_argument('--save',type=Path,help='Also benchmark a copy of an existing Space Age save')
    p.add_argument('--open',action='store_true',help='Include a Balance-window pair')
    args=p.parse_args();stage=args.stage.resolve() if args.stage else prepare()
    if not stage.is_relative_to((ROOT/'tests/out').resolve()):raise ValueError('Stage must be under tests/out')
    # Keep a second invocation from replacing hooks while an engine run is active.
    lock=(stage/'.stock-test.lock').open('a+b');lock.seek(0)
    try:msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
    except OSError:raise RuntimeError(f'Another stress-test runner owns {stage}')
    print(f'Stage: {stage}',flush=True)
    if args.settings_check:
        install(stage,'settings')
        text=execute(stage,['--benchmark',stage/'saves/_autosave-chests-1000.zip',
                            '--benchmark-ticks',10,'--benchmark-runs',1],'settings-check')
        if 'STOCK SETTINGS OK' not in text:raise RuntimeError('Native settings assertions did not complete')
        print('PASS native stock settings',flush=True)
        return
    if args.capture:
        install(stage,'capture')
        execute(stage,['--load-game',stage/'saves/_autosave-chests-50000.zip','--disable-audio','--disable-migration-window',
            '--window-size','1920x1080','--force-graphics-preset','low'],'capture',marker='STOCK STRESS CAPTURE OK')
        return
    if not args.benchmark_only:
        for count in args.counts:
            if not 0<count<=50000:raise ValueError('Supported fixture size: 1..50000')
            install(stage,'build',count)
            print(f'Building {count} chests',flush=True)
            execute(stage,['--load-game',stage/'seed.zip','--disable-audio','--disable-migration-window',
                           '--window-size','1920x1080','--force-graphics-preset','low'],f'build-{count}',
                    marker='STOCK STRESS MAP OK',timeout=1200)
    if args.build_only:return
    saves=[(f'chests-{n}',stage/f'saves/_autosave-chests-{n}.zip') for n in args.counts]
    if args.save:
        copy=stage/'space-age.zip';shutil.copyfile(args.save,copy);saves.append(('space-age',copy))
    report={'seed':20261024,'source_sha256':{str(f.relative_to(SOURCE)):hashlib.sha256(f.read_bytes()).hexdigest()
        for f in SOURCE.rglob('*') if f.is_file() and 'tools' not in f.relative_to(SOURCE).parts},'benchmarks':[]}
    for name,save in saves:
        for opened in ([False,True] if args.open else [False]):
            # Alternate order per map to reduce systematic warm-cache/order bias.
            for baseline in ([True,False] if len(report['benchmarks'])%4==0 else [False,True]):
                label=f'{name}-'+('open' if opened else 'closed')+'-'+('baseline' if baseline else 'stock')
                report['benchmarks'].append(benchmark(stage,save,label,args.ticks,args.runs,baseline,opened))
                (stage/'results.json').write_text(json.dumps(report,indent=2))
    print(f'Results: {stage / "results.json"}',flush=True)


if __name__=='__main__':main()
