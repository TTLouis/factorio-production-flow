"""Build and exercise a private SE transport save; never install into the live profile.

The adapter instruments a copied SE 0.7.64 for ground truth. Its private APIs
are fixture setup/evidence, not APIs available to a shipping companion mod.
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
import tempfile
import time
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
PROFILE = Path(os.environ['APPDATA']) / 'Factorio'
MEASUREMENT_FILES = ('se-fixture-results.json', 'se-fixture-measurements.json',
                     'se-fixture-measurements.tsv', 'se-fixture-boundary-deltas.tsv',
                     'se-fixture-sampler-history.json')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inject_verification_hook(production):
    # Normalize only the injected private copy; the clean archive keeps its bytes.
    control=production/'control.lua'
    control.write_text(control.read_text(encoding='utf-8')+'\nrequire("scripts.se_logistics_verification")\n',encoding='utf-8')


def installed_mods(directory):
    result = {}
    for path in directory.glob('*.zip'):
        with ZipFile(path) as archive:
            matches = [n for n in archive.namelist() if n.count('/') == 1 and n.endswith('/info.json')]
            if len(matches) != 1:
                continue
            info = json.loads(archive.read(matches[0]))
        if info.get('factorio_version') != '2.1':
            continue
        key = info['name']
        version = tuple(map(int, info['version'].split('.')))
        if key not in result or version > result[key]['version']:
            result[key] = {'path': path, 'info': info, 'version': version}
    return result


def prepare(args):
    engine = subprocess.check_output([str(args.exe), '--version'], text=True)
    if not re.search(r'^Version: 2\.1\.24\b', engine, re.M):
        raise ValueError('This exploratory fixture is pinned to the inspected Factorio 2.1.24 API')
    available = installed_mods(args.mods)
    if available['space-exploration']['info']['version'] != '0.7.64':
        raise ValueError('This exploratory fixture requires inspected SE 0.7.64')
    selected = set()

    def add(name):
        if name == 'base' or name in selected:
            return
        mod = available[name]
        selected.add(name)
        for dependency in mod['info'].get('dependencies', ['base']):
            dependency = dependency.strip()
            if dependency.startswith(('!', '?', '(', '+')):
                continue
            add(re.split(r'[<>=]', dependency.lstrip('~').strip())[0].strip())

    add('space-exploration')
    stage = ROOT / 'tests/out' / datetime.now().strftime('se-fixture-%Y%m%d-%H%M%S-%f')
    mods = stage / 'mods'
    mods.mkdir(parents=True)
    protected = [PROFILE / 'mods/mod-list.json', PROFILE / 'mods/mod-settings.dat', PROFILE / 'config/config.ini']
    manifest = {'engine': engine, 'pass': False, 'protected_sha256': {str(p): digest(p) for p in protected if p.is_file()},
                'mods': {}, 'fixture_only_se_instrumentation': True}
    for name in sorted(selected):
        mod = available[name]
        path = mod['path']
        manifest['mods'][name] = {'version': mod['info']['version'], 'source': str(path), 'sha256': digest(path)}
        if name == 'space-exploration':
            with ZipFile(path) as archive:
                for member in archive.infolist():
                    destination = (mods / member.filename).resolve()
                    if not destination.is_relative_to(mods.resolve()):
                        raise ValueError('Unsafe archive member')
                archive.extractall(mods)
            se = mods / ('space-exploration_' + mod['info']['version'])
            shutil.copyfile(ROOT / 'tests/development/se_transport_fixture_adapter.lua', se / 'scripts/production-flow-fixture.lua')
            with (se / 'control.lua').open('a', encoding='utf-8') as output:
                output.write('\n-- Isolated transport fixture instrumentation, never a release.\nrequire("scripts.production-flow-fixture")\n')
        else:
            shutil.copyfile(path, mods / path.name)
    production = mods / 'production-flow'
    shutil.copytree(ROOT / 'mod/production-flow', production, ignore=shutil.ignore_patterns('tools'))
    manifest['production_source_sha256'] = {p.relative_to(production).as_posix(): digest(p) for p in production.rglob('*') if p.is_file()}
    info=json.loads((production/'info.json').read_text())
    package='production-flow_'+info['version']
    with ZipFile(stage/(package+'.zip'),'w',ZIP_DEFLATED) as archive:
        for relative in sorted(manifest['production_source_sha256']):
            archive.write(production/relative,package+'/'+relative)
    manifest['candidate_sha256']=digest(stage/(package+'.zip'))
    shutil.copyfile(ROOT/'tests/development/se_logistics_verification.lua',production/'scripts/se_logistics_verification.lua')
    inject_verification_hook(production)
    fixture = mods / 'production-flow-se-fixture'
    fixture.mkdir()
    (fixture / 'info.json').write_text(json.dumps({'name': 'production-flow-se-fixture', 'version': '0.0.1',
        'title': 'Local SE transport fixture', 'author': 'Local diagnostics', 'factorio_version': '2.1',
        'dependencies': ['base >= 2.1.24', 'space-exploration = 0.7.64', 'production-flow']}), encoding='utf-8')
    shutil.copyfile(ROOT / 'tests/se_transport_fixture.lua', fixture / 'control.lua')
    enabled = selected | {'base', 'production-flow', 'production-flow-se-fixture'}
    disabled = {'space-age', 'elevated-rails', 'quality', 'recycler'}
    (mods / 'mod-list.json').write_text(json.dumps({'mods': [{'name': n, 'enabled': n in enabled}
        for n in sorted(enabled | disabled)]}, indent=2), encoding='utf-8')
    (stage / 'config.ini').write_text(
        f'[path]\nread-data={args.exe.parents[2].as_posix()}/data\nwrite-data={stage.as_posix()}\n'
        '[graphics]\nfull-screen=false\n[other]\nautosave-interval=0\nhide-achievement-popups=true\n'
        '[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale=1\n', encoding='utf-8')
    (stage / 'map-gen.json').write_text(json.dumps({'width': 256, 'height': 256, 'seed': 47113,
        'peaceful_mode': True, 'autoplace_controls': {'enemy-base': {'frequency': 0}}}), encoding='utf-8')
    (stage / 'server-settings.json').write_text(json.dumps({'name': 'Isolated SE fixture',
        'description': 'Local transport diagnostic', 'visibility': {'public': False, 'lan': False},
        'require_user_verification': False, 'auto_pause': False, 'autosave_interval': 0}), encoding='utf-8')
    manifest['fixture_source_sha256'] = {str(p.relative_to(ROOT)): digest(p) for p in
        [ROOT / 'tests/se_transport_fixture.py', ROOT / 'tests/se_transport_fixture.lua',
         ROOT / 'tests/development/se_transport_fixture_adapter.lua', ROOT / 'tests/development/se_logistics_verification.lua',
         ROOT / 'tests/development/se_logistics_capture.lua', ROOT / 'tests/development/se_dense_presentation_fixture.lua']}
    (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return stage


def run(stage, args, label, extra, marker=None):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    logfile = stage / (label + '.log')
    if logfile.exists():
        raise FileExistsError('Preserve previous evidence; use a fresh stage: ' + str(logfile))
    command = [str(args.exe), '--config', str(stage / 'config.ini'), '--mod-directory', str(stage / 'mods'), *map(str, extra)]
    print('Running ' + label + ': ' + str(stage), flush=True)
    with logfile.open('w', encoding='utf-8') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, startupinfo=startup,
                                   env=dict(os.environ, SteamAppId='427520', SteamGameId='427520'))
        deadline = time.monotonic() + (args.gui_timeout if label == "gui" else args.timeout)
        try:
            while process.poll() is None:
                text = logfile.read_text(encoding='utf-8', errors='replace')
                if 'Error while' in text or 'Error ModManager' in text or 'SE FIXTURE FAIL' in text:
                    raise RuntimeError(text[-5000:])
                if marker and marker in text and 'Saving finished' in text[text.index(marker):]:
                    return text
                if time.monotonic() > deadline:
                    raise TimeoutError(str(logfile))
                time.sleep(0.5)
            text = logfile.read_text(encoding='utf-8', errors='replace')
            if process.returncode or marker and marker not in text:
                raise RuntimeError(text[-5000:])
            return text
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=20)


def validate_measurements(stage, output=None):
    """Validate real engine/export evidence, never substitute presentation data."""
    output = output or stage / 'script-output'
    for name in MEASUREMENT_FILES:
        if not (output / name).is_file():
            raise AssertionError('Missing measured fixture evidence: ' + name)
    result = json.loads((output / 'se-fixture-results.json').read_text(encoding='utf-8'))
    measured = json.loads((output / 'se-fixture-measurements.json').read_text(encoding='utf-8'))
    provenance = measured['provenance']
    assert provenance['no_statistics_or_history_injection'] is True
    assert provenance['physical_basis'] == 'physical-storage-v2'
    samples = measured['samples']
    assert len(samples) >= 50 and all(a['tick'] < b['tick'] for a, b in zip(samples, samples[1:]))
    assert all(b['tick'] - a['tick'] == provenance['sample_interval_ticks'] for a, b in zip(samples, samples[1:]))
    first, last = samples[0], samples[-1]
    factory = measured['factory']
    assert len(factory['machines']) >= 7 and factory['belts'] > 0 and factory['inserters'] > 0
    for machine in factory['machines']:
        role = machine['role']
        assert last['machines'][role]['products_finished'] > first['machines'][role]['products_finished'], role

    def amount(stacks, name):
        return sum(stack['count'] for stack in stacks if stack['name'] == name)

    assert amount(last['chests']['iron-ore-feed-1'], 'iron-ore') < amount(first['chests']['iron-ore-feed-1'], 'iron-ore')
    assert amount(last['chests']['iron-plate-stock-3'], 'iron-plate') > amount(first['chests']['iron-plate-stock-3'], 'iron-plate')
    assert amount(last['chests']['gear-output'], 'iron-gear-wheel') > 0
    assert amount(last['chests']['circuit-output'], 'electronic-circuit') > 0
    counts = result['contract']['counts']
    boundaries = measured['stat_deltas']
    boundary_counts, statistics_deltas = {}, {}
    for boundary in boundaries:
        kind = boundary['kind']
        boundary_counts[kind] = boundary_counts.get(kind, 0) + 1
        totals = statistics_deltas.setdefault(kind, {})
        for scope in boundary['surfaces']:
            for item, delta in boundary['stats_delta'][scope].items():
                before, after = boundary['stats_before'][scope][item], boundary['stats_after'][scope][item]
                assert all(delta[side] == after[side] - before[side] for side in ('made', 'used'))
                total = totals.setdefault(item, {'made': 0, 'used': 0})
                for side in ('made', 'used'):
                    total[side] += delta[side]
                for prefix in ('physical', 'physical_chests'):
                    old_values = boundary[prefix + '_before'][scope]
                    new_values = boundary[prefix + '_after'][scope]
                    old = old_values.get(item, 0) if isinstance(old_values, dict) else 0
                    new = new_values.get(item, 0) if isinstance(new_values, dict) else 0
                    assert boundary[prefix + '_delta'][scope][item] == new - old
    assert boundary_counts == {'rocket_dispatch': counts['rockets'], 'rocket_arrival': counts['rockets'],
                               'cannon_dispatch': counts['cannon_shots'], 'cannon_arrival': counts['cannon_shots']}
    receipts = validate_receipts(result)
    sampler = json.loads((output / 'se-fixture-sampler-history.json').read_text(encoding='utf-8'))
    scans, scan_provenance = sampler['stock_scans'], sampler['provenance']
    assert scan_provenance['synthetic'] is False and scan_provenance['scans'] == len(scans) >= 15
    assert scan_provenance['basis'] == 'physical-storage-v2'
    assert all(b['tick'] - a['tick'] >= scan_provenance['cooldown_ticks'] for a, b in zip(scans, scans[1:]))
    for name in ('se-fixture-measurements.tsv', 'se-fixture-boundary-deltas.tsv'):
        assert len((output / name).read_text(encoding='utf-8').splitlines()) > 100
    return {'pass': True, 'synthetic': False, 'factory_machines': len(factory['machines']),
            'samples': len(samples), 'first_tick': first['tick'], 'last_tick': last['tick'],
            'completed_stock_scans': len(scans), 'stock_basis': scan_provenance['basis'],
            'boundary_counts': boundary_counts, 'observed_item_statistics_deltas': statistics_deltas,
            'receipts': receipts}


def _stacks(value):
    # Factorio serialises an empty Lua table as an object, a list otherwise.
    items = value.values() if isinstance(value, dict) else (value or [])
    totals = {}
    for stack in items:
        quality = stack.get('quality') or 'normal'
        if isinstance(quality, dict):
            quality = quality.get('name', 'normal')
        key = (stack['name'], quality)
        totals[key] = totals.get(key, 0) + stack['count']
    return totals


def _xy(position):
    if isinstance(position, dict):
        return position['x'], position['y']
    return position[0], position[1]


def validate_receipts(result):
    """Compare Production Flow's public receipts with private SE ground truth."""
    counts = result['contract']['counts']
    truth = result['truth'].values() if isinstance(result['truth'], dict) else result['truth']
    production = result['production']
    rockets = production['rocket_receipts']
    cannons = production['cannon_receipts']
    assert len(rockets) == counts['rockets'] and len(cannons) == counts['cannon_shots']
    by_landing = {(r['unit'], r.get('landed_tick')): r for r in rockets}
    assert len(by_landing) == len(rockets), 'Rocket landings not distinct'
    pad_receipts = padless = 0
    for land in (t for t in truth if t['kind'] == 'rocket_land'):
        # The same tick proves Production Flow settled during SE's landing tick.
        record = by_landing.get((land['unit'], land['tick']))
        assert record, 'Landing not settled on its tick: %s' % land
        if land['had_pad']:
            assert record['status'] == 'received' and record['receipt'] == 'pad', record
            assert record['arrival_tick'] == land['tick']
            assert _stacks(record['received']) == _stacks(land['surviving_manifest']),                 'Rocket receipt differs from SE surviving cargo: %s' % land['unit']
            pad_receipts += 1
        else:
            assert record.get('received') is None and record['status'] == 'padless', record
            padless += 1
    caught = spilled = 0
    for land in (t for t in truth if t['kind'] == 'cannon_land'):
        tx, ty = _xy(land['position'])
        matches = [c for c in cannons if c['eta'] == land['tick'] and c['destination']['zone'] == land['target']
                   and abs(_xy(c['destination']['position'])[0] - tx) < 1 / 256
                   and abs(_xy(c['destination']['position'])[1] - ty) < 1 / 256]
        assert len(matches) == 1, 'Cannon landing not paired exactly once: %s' % land
        shot = matches[0]
        assert _stacks(shot['sent']) == {(land['item'], land['quality']): land['count']}, shot
        if land.get('receiver'):
            assert land['caught'] == land['count']
            assert shot['status'] == 'received' and shot['arrival_tick'] == land['tick'] and shot['receiver'] == land['receiver']
            assert _stacks(shot['received']) == {(land['item'], land['quality']): land['caught']}
            caught += 1
        else:
            assert shot['status'] == 'spilled' and shot.get('received') is None, shot
            spilled += 1
    assert pad_receipts + padless == counts['rockets'] and padless >= 1 and pad_receipts >= 1
    assert caught + spilled == counts['cannon_shots'] and spilled == 1
    return {'rocket_pad_receipts': pad_receipts, 'rocket_padless_unknown': padless,
            'cannon_received': caught, 'cannon_spilled': spilled}



def artifact_hashes(stage):
    return {p.relative_to(stage).as_posix(): digest(p) for p in stage.rglob('*')
            if p.is_file() and (p.suffix == '.log' or p.suffix == '.zip' and 'mods' not in p.relative_to(stage).parts
                or p.suffix in {'.json', '.tsv'} and 'script-output' in p.relative_to(stage).parts)}


def physical_source_paths(stage, manifest):
    se_version = manifest['mods']['space-exploration']['version']
    return {
        'tests/se_transport_fixture.lua': stage / 'mods/production-flow-se-fixture/control.lua',
        'tests/development/se_transport_fixture_adapter.lua': stage / ('mods/space-exploration_' + se_version) / 'scripts/production-flow-fixture.lua',
        'tests/development/se_logistics_verification.lua': stage / 'mods/production-flow/scripts/se_logistics_verification.lua',
    }


def validate_staged_production(stage, manifest, clean_files):
    """Bind physical proof to loaded code, allowing only our exact test hooks."""
    production = stage / 'mods/production-flow'
    expected = {relative: hashlib.sha256(data).hexdigest() for relative, data in clean_files.items()}
    control = clean_files['control.lua'].decode('utf-8').replace('\r\n', '\n')
    control += '\nrequire("scripts.se_logistics_verification")\n'
    hooks = manifest['fixture_source_sha256']

    def fixture_hash(name):
        relative = 'tests/development/' + name
        value = hooks.get(relative, hooks.get(str(Path(relative))))
        assert value, 'Missing recorded fixture source: ' + relative
        return value

    expected['scripts/se_logistics_verification.lua'] = fixture_hash('se_logistics_verification.lua')
    controls = [control]
    if manifest.get('gui_hook_sha256'):
        # Recreate locale helpers from the archived source, not today's catalogs.
        # Temporary validation files never modify the stage or its evidence.
        from localization_check import install_native_support
        output = ROOT / 'tests/out'
        with tempfile.TemporaryDirectory(prefix='se-source-check-', dir=output) as directory:
            scratch = Path(directory)
            for relative, data in clean_files.items():
                destination = (scratch / relative).resolve()
                assert destination.is_relative_to(scratch.resolve()), 'Unsafe candidate member: ' + relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
            install_native_support(scratch, 'en', mod=scratch)
            for path in (scratch / 'scripts').glob('test_locale*.lua'):
                relative = path.relative_to(scratch).as_posix()
                assert relative not in clean_files, 'Native helper present in clean candidate: ' + relative
                expected[relative] = digest(path)
        for name in ('se_logistics_capture.lua', 'se_dense_presentation_fixture.lua'):
            recorded = fixture_hash(name)
            assert manifest['gui_hook_sha256'].get(name) == recorded, 'GUI hook provenance differs: ' + name
            expected['scripts/' + name] = recorded
        handler = 'function(e) UI.on_string_translated(e) end'
        assert control.count(handler) == 1, 'Unrecognized native locale event wiring'
        control = 'local NativeLocale=require("scripts.test_locale_native")\n' + control.replace(
            handler, 'function(e) NativeLocale.on_translated(e); UI.on_string_translated(e) end')
        controls = [control + '\nrequire("scripts.se_logistics_capture").register(UI' + config + ')\n'
                    for config in ('', ',{focused=true}')]
    actual = {path.relative_to(production).as_posix(): digest(path)
              for path in production.rglob('*') if path.is_file()}
    assert set(actual) == set(expected), 'Staged Production Flow file set changed'
    assert actual['control.lua'] in {hashlib.sha256(text.replace('\n', os.linesep).encode('utf-8')).hexdigest()
                                     for text in controls}, 'Staged Production Flow control changed'
    for relative, recorded in expected.items():
        if relative != 'control.lua':
            assert actual[relative] == recorded, 'Staged Production Flow source changed: ' + relative


def validate_physical_sources(stage, manifest):
    archives = list(stage.glob('production-flow_*.zip'))
    assert len(archives) == 1 and digest(archives[0]) == manifest['candidate_sha256'], 'Clean candidate archive changed'
    with ZipFile(archives[0]) as archive:
        assert archive.testzip() is None
        files = {n.split('/', 1)[1]: hashlib.sha256(archive.read(n)).hexdigest()
                 for n in archive.namelist() if not n.endswith('/')}
        assert files == manifest['production_source_sha256'], 'Clean candidate/source mismatch'
        clean_files = {n.split('/', 1)[1]: archive.read(n) for n in archive.namelist() if not n.endswith('/')}
    validate_staged_production(stage, manifest, clean_files)
    source_hashes = {}
    for relative, staged in physical_source_paths(stage, manifest).items():
        expected = manifest['fixture_source_sha256'][str(Path(relative))]
        assert digest(staged) == expected, 'Physical fixture source changed: ' + relative
        source_hashes[relative] = expected
    for name, mod in manifest['mods'].items():
        original = Path(mod['source'])
        assert digest(original) == mod['sha256'], 'Original mod archive changed: ' + name
        if name != 'space-exploration':
            assert digest(stage / 'mods' / original.name) == mod['sha256'], 'Staged dependency changed: ' + name
        else:
            with ZipFile(original) as archive:
                expected_files = set()
                for member in archive.infolist():
                    if member.is_dir():
                        continue
                    expected_files.add(member.filename)
                    expected = archive.read(member)
                    if member.filename.endswith('/control.lua') and member.filename.count('/') == 1:
                        expected += ('\n-- Isolated transport fixture instrumentation, never a release.\nrequire("scripts.production-flow-fixture")\n').replace('\n', os.linesep).encode('utf-8')
                    assert digest(stage / 'mods' / member.filename) == hashlib.sha256(expected).hexdigest(), 'Staged SE source changed: ' + member.filename
                root = next(iter(expected_files)).split('/')[0]
                actual_files = {(p.relative_to(stage / 'mods')).as_posix() for p in (stage / 'mods' / root).rglob('*') if p.is_file()}
                assert actual_files == expected_files | {root + '/scripts/production-flow-fixture.lua'}
    return source_hashes


def physical_evidence(stage, manifest, output):
    source_hashes = validate_physical_sources(stage, manifest)
    protected = {p: Path(p).is_file() and digest(Path(p)) == h for p, h in manifest['protected_sha256'].items()}
    assert all(protected.values()), 'Live profile changed'
    build = (stage / 'build.log').read_text(encoding='utf-8', errors='replace')
    assert 'SE FIXTURE READY ' in build and 'Goodbye' in build
    for phase, marker in [('launch', 'SE FIXTURE CHECKPOINT '), ('resume', 'SE FIXTURE PASS ')]:
        text = (stage / (phase + '.log')).read_text(encoding='utf-8', errors='replace')
        assert marker in text and 'Saving finished' in text[text.index(marker):], 'Missing native completed-save marker: ' + phase
        assert not any(error in text for error in ('Error while', 'Error ModManager', 'SE FIXTURE FAIL'))
    required = ['fixture-ready.zip', 'saves/_autosave-se-fixture-inflight.zip', 'saves/_autosave-se-fixture-complete.zip',
                'build.log', 'launch.log', 'resume.log']
    for relative in required[:3]:
        with ZipFile(stage / relative) as archive:
            assert archive.testzip() is None, 'Corrupt native save: ' + relative
    validation = validate_measurements(stage, output)
    return {'native_phase_sha256': {name: digest(stage / name) for name in required},
            'measurement_sha256': {name: digest(output / name) for name in MEASUREMENT_FILES},
            'candidate_sha256': manifest['candidate_sha256'], 'physical_source_sha256': source_hashes,
            'protected_unchanged': protected, 'factory_validation': validation}


def verify_recorded_physical(stage, manifest):
    checkpoint = manifest.get('physical_evidence')
    output = stage / 'physical-evidence' if checkpoint else stage / 'script-output'
    observed = physical_evidence(stage, manifest, output)
    if checkpoint:
        for key in ('native_phase_sha256', 'measurement_sha256', 'candidate_sha256', 'physical_source_sha256'):
            assert observed[key] == checkpoint[key], 'Verified physical evidence changed: ' + key
    return observed, output


def record_physical_checkpoint(stage, manifest, origin):
    target = stage / 'physical-evidence'
    if target.exists():
        proof, _ = verify_recorded_physical(stage, manifest)
    else:
        proof = physical_evidence(stage, manifest, stage / 'script-output')
        target.mkdir()
        for name in MEASUREMENT_FILES:
            shutil.copy2(stage / 'script-output' / name, target / name)
    proof.update({'verified_at': datetime.now().astimezone().isoformat(), 'verification_origin': origin})
    manifest['physical_verified'] = True
    manifest['physical_evidence'] = proof
    manifest['factory_validation'] = proof['factory_validation']
    manifest['protected_unchanged'] = proof['protected_unchanged']
    manifest['measurement_exports_sha256'] = {name: digest(stage / 'script-output' / name) for name in MEASUREMENT_FILES}
    manifest['artifacts_sha256'] = artifact_hashes(stage)
    (target / 'checkpoint.json').write_text(json.dumps(proof, indent=2), encoding='utf-8')
    (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('SE PHYSICAL FIXTURE VERIFIED: ' + str(stage), flush=True)


def promote_physical_stage(stage):
    stage = stage.resolve()
    assert stage.is_relative_to((ROOT / 'tests/out').resolve()) and stage.name.startswith('se-fixture-')
    manifest_path = stage / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    assert not manifest.get('pass') and (stage / 'gui.log').is_file(), 'Promotion is for interrupted GUI stages; overall pass is preserved'
    backup = stage / ('manifest-before-physical-promotion-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json')
    shutil.copy2(manifest_path, backup)
    record_physical_checkpoint(stage, manifest, 'post-interruption validation of native phase artifacts; GUI incomplete')
    assert manifest['pass'] is False, 'Physical promotion must not claim GUI/full pass'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=Path('D:/SteamLibrary/steamapps/common/Factorio/bin/x64/Factorio.exe'))
    parser.add_argument('--mods', type=Path, default=PROFILE / 'mods')
    parser.add_argument('--timeout', type=int, default=240)
    parser.add_argument('--gui-timeout', type=int, default=900, help='Graphical capture timeout in seconds')
    parser.add_argument('--record-physical-checkpoint', action='store_true', help='Opt in to a separately verified physical checkpoint before GUI capture')
    parser.add_argument('--promote-physical-stage', type=Path, help='Validate an interrupted GUI stage and record only its physical checkpoint; invokes no engine')
    parser.add_argument('--capture',action='store_true',help='Capture native Logistics UI after the functional run')
    parser.add_argument('--focused-capture',action='store_true',help='Exercise all GUI cases, capturing stock, graph, exchange-axis and labelled receipt-marker views')
    parser.add_argument('--capture-from',type=Path,help='Reuse a verified physical fixture in a fresh isolated GUI stage')
    args = parser.parse_args()
    if args.promote_physical_stage:
        assert not args.capture and not args.capture_from
        promote_physical_stage(args.promote_physical_stage)
        return
    stage = prepare(args)
    manifest = json.loads((stage / 'manifest.json').read_text())
    try:
        if args.capture_from:
            assert args.capture, '--capture-from requires --capture'
            previous=args.capture_from.resolve()
            previous_manifest=json.loads((previous/'manifest.json').read_text())
            assert previous_manifest.get('pass') or previous_manifest.get('physical_verified'), 'Source has no full pass or verified physical checkpoint'
            previous_proof, previous_output = verify_recorded_physical(previous, previous_manifest)
            assert previous_manifest['production_source_sha256']==manifest['production_source_sha256']
            assert previous_manifest['engine']==manifest['engine']
            assert {n:v['sha256'] for n,v in previous_manifest['mods'].items()}=={n:v['sha256'] for n,v in manifest['mods'].items()}
            for path in ['tests/se_transport_fixture.lua','tests/development/se_transport_fixture_adapter.lua','tests/development/se_logistics_verification.lua']:
                key=str(Path(path))
                assert previous_manifest['fixture_source_sha256'][key]==manifest['fixture_source_sha256'][key]
            save=previous/'saves/_autosave-se-fixture-complete.zip'
            assert digest(save)==previous_proof['native_phase_sha256']['saves/_autosave-se-fixture-complete.zip']
            (stage/'saves').mkdir();shutil.copy2(save,stage/'saves'/save.name)
            shutil.copy2(previous/'fixture-ready.zip',stage/'fixture-ready.zip')
            shutil.copy2(previous/'saves/_autosave-se-fixture-inflight.zip',stage/'saves/_autosave-se-fixture-inflight.zip')
            for phase in ['build','launch','resume']:
                shutil.copy2(previous/(phase+'.log'),stage/(phase+'.log'))
            output = stage / 'script-output'
            output.mkdir()
            for name in MEASUREMENT_FILES:
                source = previous_output / name
                assert digest(source) == previous_proof['measurement_sha256'][name]
                shutil.copy2(source, output / name)
            shutil.copy2(previous/'manifest.json',stage/'physical-source-manifest.json')
            manifest['physical_fixture_reused_from']={'stage':str(previous),'save_sha256':digest(save),
                'manifest_sha256':digest(previous/'manifest.json')}
            print('Reusing verified physical fixture: '+str(previous),flush=True)
        else:
            run(stage, args, 'build', ['--create', stage / 'fixture-ready.zip', '--map-gen-settings', stage / 'map-gen.json'])
            common = ['--server-settings', stage / 'server-settings.json', '--bind', '127.0.0.1', '--port', '34198', '--disable-audio']
            run(stage, args, 'launch', ['--start-server', stage / 'fixture-ready.zip', *common], 'SE FIXTURE CHECKPOINT')
            checkpoint = stage / 'saves/_autosave-se-fixture-inflight.zip'
            run(stage, args, 'resume', ['--start-server', checkpoint, *common], 'SE FIXTURE PASS')
        if args.record_physical_checkpoint:
            record_physical_checkpoint(stage, manifest, 'native physical run' if not args.capture_from else 'revalidated physical fixture copy')
        else:
            manifest['factory_validation'] = validate_measurements(stage)
            manifest['measurement_exports_sha256'] = {name: digest(stage / 'script-output' / name) for name in MEASUREMENT_FILES}
        if args.capture:
            from localization_check import install_native_support
            production=stage/'mods/production-flow'
            install_native_support(production,'en')
            shutil.copyfile(ROOT/'tests/development/se_logistics_capture.lua',production/'scripts/se_logistics_capture.lua')
            shutil.copyfile(ROOT/'tests/development/se_dense_presentation_fixture.lua',production/'scripts/se_dense_presentation_fixture.lua')
            manifest['gui_hook_sha256']={name:digest(production/'scripts'/name) for name in
                ['se_logistics_capture.lua','se_dense_presentation_fixture.lua']}
            for name, value in manifest['gui_hook_sha256'].items():
                manifest['fixture_source_sha256']['tests/development/'+name]=value
            control=(production/'control.lua').read_text(encoding='utf-8')
            control=control.replace('function(e) UI.on_string_translated(e) end',
                'function(e) require("scripts.test_locale_native").on_translated(e); UI.on_string_translated(e) end')
            # Require at control parsing time, never in the runtime handler.
            control=control.replace('require("scripts.test_locale_native").on_translated(e)', 'NativeLocale.on_translated(e)')
            control='local NativeLocale=require("scripts.test_locale_native")\n'+control
            capture_config=',{focused=true}' if args.focused_capture else ''
            (production/'control.lua').write_text(control+'\nrequire("scripts.se_logistics_capture").register(UI'+capture_config+')\n',encoding='utf-8')
            with (stage/'config.ini').open('a',encoding='utf-8') as output:output.write('[general]\nlocale=en\n')
            run(stage,args,'gui',['--load-game',stage/'saves/_autosave-se-fixture-complete.zip',
                '--disable-audio','--disable-migration-window','--force-graphics-preset','low','--window-size','1920x1080'], 'SE LOGISTICS GUI PASS')
            manifest['captures_sha256']={p.name:digest(p) for p in (stage/'script-output/se-logistics').glob('*.png')}
            gui_result=json.loads((stage/'script-output/se-logistics/gui.json').read_text())
            assert len(manifest['captures_sha256'])==len(gui_result['captures'])
            assert gui_result['stock_layout']['synthetic'] is False
            assert all('synthetic' in name for name in gui_result['synthetic_captures'])
            assert gui_result['graph_history']['origin'] == 'balance'
            assert gui_result['factory_world']['synthetic'] is False
            assert gui_result['exchange_axis']['slot_pixels']==24 and gui_result['exchange_axis']['visible_exchanges']>4
            assert gui_result['import_marker_contract']['synthetic'] and gui_result['import_marker_contract']['markers']>0
            assert gui_result['import_marker_fixture']['restored']
            assert all(gui_result['graphs'][view]['imports'] == 0 and gui_result['graphs'][view]['exports'] > 0
                       and gui_result['graphs'][view]['external_supply_targets'] >= 2
                       for view in ('balance', 'focus', 'sankey'))
            manifest['factory_validation_after_gui'] = validate_measurements(stage)
            manifest['measurement_exports_sha256'] = {name: digest(stage / 'script-output' / name) for name in MEASUREMENT_FILES}
        manifest['pass'] = True
    finally:
        manifest['protected_unchanged'] = {p: digest(Path(p)) == h for p, h in manifest['protected_sha256'].items()}
        manifest['artifacts_sha256'] = artifact_hashes(stage)
        (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
        assert all(manifest['protected_unchanged'].values()), 'Live profile changed'
    print('SE FIXTURE PASS: ' + str(stage), flush=True)


if __name__ == '__main__':
    main()
