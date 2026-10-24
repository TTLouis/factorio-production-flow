"""Isolated Space Age save -> 10-minute history -> real GUI capture loop.

Only copies are loaded. The live save, mods and configuration are hashed and
checked after every run. No downloads, live installation or desktop input.
"""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
PROFILE = Path(os.environ['APPDATA']) / 'Factorio'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save_mods(path):
    # Bounded reader for the observed Factorio 2.0/2.1 level-init header.
    # Reject unfamiliar layouts rather than guessing a mod configuration.
    with ZipFile(path) as archive:
        entry = next(n for n in archive.namelist() if n.endswith('/level-init.dat'))
        with archive.open(entry) as stream:
            data = stream.read(32768)
    start = data.index(b'\x04base', 32)
    count, cursor, result = data[start - 1], start, {}
    if not 1 <= count < 255:
        raise ValueError('Unsupported save header')
    for _ in range(count):
        length = data[cursor]
        name = data[cursor + 1:cursor + 1 + length].decode('utf-8')
        if not re.fullmatch(r'[A-Za-z0-9_ .-]+', name) or name in result:
            raise ValueError('Unsupported save mod table')
        cursor += 1 + length
        result[name] = '.'.join(map(str, data[cursor:cursor + 3]))
        cursor += 7
    return result


def prepare(args):
    stage = ROOT / 'tests/out' / datetime.now().strftime('save-test-%Y%m%d-%H%M%S-%f')
    mods = stage / 'mods'
    mods.mkdir(parents=True)
    saved = save_mods(args.save)
    builtin = {'base', 'elevated-rails', 'quality', 'space-age', 'recycler'}
    if 'space-age' not in saved or set(saved) - builtin:
        raise ValueError('This runner requires a Space Age save using only bundled mods')
    protected = [args.save, PROFILE / 'mods/mod-list.json', PROFILE / 'mods/mod-settings.dat', PROFILE / 'config/config.ini']
    original = {str(p.resolve()): digest(p) for p in protected if p.is_file()}
    shutil.copyfile(args.save, stage / 'input.zip')
    version = subprocess.check_output([str(args.exe), '--version'], text=True)
    series = re.search(r'Version: (\d+\.\d+)\.', version)[1]
    source = ROOT / 'mod/production-flow'
    target = mods / 'production-flow'
    shutil.copytree(source, target, ignore=shutil.ignore_patterns('tools'))
    info = json.loads((target / 'info.json').read_text())
    original_series = info['factorio_version']
    # Compatibility probe only: never rewrite the source/release manifest.
    info['factorio_version'] = series
    (target / 'info.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
    enabled = set(saved)
    if series == '2.1':
        enabled.add('recycler')
    (mods / 'mod-list.json').write_text(json.dumps({'mods': [
        {'name': n, 'enabled': n in enabled or n == 'production-flow'}
        for n in sorted(builtin | {'production-flow'})]}), encoding='utf-8')
    (stage / 'config.ini').write_text(
        f'[path]\nread-data={args.exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n'
        '[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\nhide-achievement-popups=true\n', encoding='utf-8')
    manifest = {'source_save': str(args.save), 'saved_mods': saved, 'engine': version,
                'source_factorio_version': original_series, 'staged_factorio_version': series,
                'protected_sha256': original, 'input_sha256': digest(stage / 'input.zip')}
    (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return stage


def install_hook(stage, phase):
    target = stage / 'mods/production-flow'
    source = ROOT / 'mod/production-flow'
    # Refresh runtime code for the edit/retest loop, keeping isolated metadata.
    shutil.copytree(source, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns('tools'))
    manifest = json.loads((stage / 'manifest.json').read_text())
    info = json.loads((target / 'info.json').read_text())
    info['factorio_version'] = manifest['staged_factorio_version']
    (target / 'info.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
    manifest['tested_source_sha256'] = {str(p.relative_to(source)): digest(p)
        for p in source.rglob('*') if p.is_file() and 'tools' not in p.relative_to(source).parts}
    package_name = f"production-flow_{info['version']}"
    package = stage / f'{package_name}.zip'
    with ZipFile(package, 'w', ZIP_DEFLATED) as archive:
        for relative in sorted(manifest['tested_source_sha256']):
            archive.write(source / relative, package_name + '/' + Path(relative).as_posix())
    manifest['candidate_package'] = package.name
    manifest['candidate_sha256'] = digest(package)
    (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    shutil.copyfile(ROOT / 'tests/save_test.lua', target / 'scripts/save_test.lua')
    (target / 'scripts/save_test_mode.lua').write_text(f'return "{phase}"\n', encoding='utf-8')
    control = (source / 'control.lua').read_text(encoding='utf-8')
    needle = '  Sampler.on_tick(e.tick)'
    assert control.count(needle) == 1
    control = 'local SaveTest = require("scripts.save_test")\n' + control.replace(
        needle, needle + '\n  SaveTest.tick(UI, Sampler)')
    (target / 'control.lua').write_text(control, encoding='utf-8')


def run(stage, args, phase):
    install_hook(stage, phase)
    active_mods = stage / 'mods'
    if phase == 'warmup':
        # A fresh installation must not inherit this stage's older saved
        # diagnostic-export preference. Keep those settings intact for reload tests.
        active_mods = stage / 'warmup-mods' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        shutil.copytree(stage / 'mods/production-flow', active_mods / 'production-flow')
        shutil.copyfile(stage / 'mods/mod-list.json', active_mods / 'mod-list.json')
    common = [str(args.exe), '--config', str(stage / 'config.ini'), '--mod-directory', str(active_mods)]
    environment = dict(os.environ, SteamAppId='427520', SteamGameId='427520')
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    if phase == 'history':
        # Benchmark suppresses autosaves, and --until-tick uses an engine tick
        # counter which need not match LuaGameScript.tick on an old save.
        # A hidden local game preserves the exact sampled history for reload.
        manifest = json.loads((stage / 'manifest.json').read_text())
        original = Path(manifest['source_save'])
        if digest(original) != manifest['protected_sha256'][str(original.resolve())]:
            raise RuntimeError('Source save changed since this test stage was created')
        shutil.copyfile(original, stage / 'input.zip')
        command = [*common, '--load-game', str(stage / 'input.zip'), '--window-size', '1920x1080',
                   '--disable-audio', '--disable-migration-window', '--force-graphics-preset', 'low']
        marker = 'SANKEY SAVE HISTORY OK'
    else:
        warmed = stage / ('input.zip' if phase == 'warmup' else 'saves/_autosave-sankey-warmed.zip')
        if not warmed.is_file():
            raise FileNotFoundError(f'Run history phase first: {warmed}')
        command = [*common, '--load-game', str(warmed), '--window-size', '1920x1080',
                   '--disable-audio', '--disable-migration-window', '--force-graphics-preset', 'low']
        marker = 'SANKEY SAVE GUI OK'
    logfile = stage / f'{phase}.log'
    if logfile.exists():
        shutil.copyfile(logfile, stage / (phase + datetime.now().strftime('-%Y%m%d-%H%M%S.log')))
    print(f'Running {phase}: {stage}', flush=True)
    started = time.time()
    with logfile.open('w', encoding='utf-8') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, env=environment, startupinfo=startup)
        deadline = time.monotonic() + args.timeout
        try:
            while time.monotonic() < deadline:
                log = logfile.read_text(encoding='utf-8', errors='replace')
                if marker in log:
                    if phase == 'history':
                        warmed = stage / 'saves/_autosave-sankey-warmed.zip'
                        # Wait for Factorio to finish the asynchronous save.
                        if not warmed.is_file() or warmed.stat().st_mtime < started or 'Saving finished' not in log:
                            time.sleep(1)
                            continue
                        with ZipFile(warmed) as archive:
                            if archive.testzip() is not None:
                                raise RuntimeError('Warmed save failed its ZIP integrity check')
                    if phase != 'history':
                        folder = stage / 'script-output/save-test'
                        result = json.loads((folder / 'gui.json').read_text())
                        if not result['captures']:
                            raise RuntimeError('No GUI views captured')
                        for name in result['captures']:
                            shot = folder / f'{name}.png'
                            if not shot.is_file() or shot.stat().st_mtime < started or shot.stat().st_size < 10000:
                                raise RuntimeError(f'Missing, stale or empty screenshot: {shot}')
                        evidence = dict(result, phase=phase,
                            candidate_sha256=json.loads((stage / 'manifest.json').read_text())['candidate_sha256'],
                            captures_sha256={name: digest(folder / f'{name}.png') for name in result['captures']})
                        (folder / f'evidence-{phase}.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')
                    print(f'PASS {phase}', flush=True)
                    return
                if process.poll() is not None or 'Error while' in log or 'Error ModManager' in log:
                    raise RuntimeError(log[-7000:])
                time.sleep(1)
            raise TimeoutError(f'{phase} exceeded {args.timeout}s; see {logfile}')
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--save', type=Path, default=PROFILE / 'saves/_autosave4.zip')
    parser.add_argument('--exe', type=Path, default=Path(r'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\Factorio.exe'))
    parser.add_argument('--stage', type=Path, help='Reuse a previously isolated stage for iteration')
    parser.add_argument('--phase', choices=['all', 'history', 'gui', 'balance', 'full', 'picker', 'scroll', 'names', 'audit', 'ux', 'warmup'], default='all')
    parser.add_argument('--timeout', type=int, default=1200)
    args = parser.parse_args()
    stage = args.stage.resolve() if args.stage else prepare(args)
    if not stage.is_relative_to((ROOT / 'tests/out').resolve()):
        raise ValueError('Test stage must be inside this project tests/out directory')
    manifest = json.loads((stage / 'manifest.json').read_text())
    try:
        for phase in (['history', 'gui'] if args.phase == 'all' else [args.phase]):
            run(stage, args, phase)
    finally:
        changed = [p for p, sha in manifest['protected_sha256'].items() if digest(Path(p)) != sha]
        if changed:
            raise RuntimeError(f'Protected input changed externally or during test: {changed}')
        print('Original save, mod list, settings and config hashes unchanged.', flush=True)
        print(f'Evidence: {stage}', flush=True)


if __name__ == '__main__':
    main()
