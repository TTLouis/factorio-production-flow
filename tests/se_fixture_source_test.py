"""Bind reusable native evidence to the code actually loaded by the stage."""
import os
from pathlib import Path
import tempfile
import unittest

from localization_check import install_native_support
from se_transport_fixture import ROOT, digest, inject_verification_hook, validate_staged_production


class StagedProductionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = ROOT / 'mod/production-flow'
        cls.clean = {p.relative_to(source).as_posix(): p.read_bytes()
                     for p in source.rglob('*') if p.is_file() and 'tools' not in p.relative_to(source).parts}

    def setUp(self):
        output = ROOT / 'tests/out'
        output.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='se-source-test-', dir=output)
        self.addCleanup(self.temporary.cleanup)
        self.stage = Path(self.temporary.name)
        self.production = self.stage / 'mods/production-flow'
        for relative, data in self.clean.items():
            path = self.production / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.manifest = {'fixture_source_sha256': {}}
        self.hook('se_logistics_verification.lua')
        self.control = self.clean['control.lua'].decode('utf-8').replace('\r\n', '\n')
        self.control += '\nrequire("scripts.se_logistics_verification")\n'
        self.write_control()

    def hook(self, name):
        original = ROOT / 'tests/development' / name
        (self.production / 'scripts' / name).write_bytes(original.read_bytes())
        self.manifest['fixture_source_sha256'][str(Path('tests/development') / name)] = digest(original)

    def write_control(self):
        (self.production / 'control.lua').write_bytes(self.control.replace('\n', os.linesep).encode('utf-8'))

    def capture(self, focused):
        install_native_support(self.production, 'en')
        self.manifest['gui_hook_sha256'] = {}
        for name in ('se_logistics_capture.lua', 'se_dense_presentation_fixture.lua'):
            self.hook(name)
            self.manifest['gui_hook_sha256'][name] = digest(self.production / 'scripts' / name)
        self.control = 'local NativeLocale=require("scripts.test_locale_native")\n' + self.control.replace(
            'function(e) UI.on_string_translated(e) end',
            'function(e) NativeLocale.on_translated(e); UI.on_string_translated(e) end')
        self.control += '\nrequire("scripts.se_logistics_capture").register(UI' + (',{focused=true}' if focused else '') + ')\n'
        self.write_control()

    def validate(self):
        validate_staged_production(self.stage, self.manifest, self.clean)

    def test_physical_stage_accepts_only_expected_verification_hook(self):
        self.validate()

    def test_lf_clean_control_is_staged_in_the_exact_validated_form(self):
        (self.production/'control.lua').write_bytes(self.clean['control.lua'].replace(b'\r\n',b'\n'))
        inject_verification_hook(self.production)
        self.validate()

    def test_both_capture_modes_accept_exact_native_hooks(self):
        for focused in (False, True):
            with self.subTest(focused=focused):
                self.capture(focused)
                self.validate()
                if not focused:
                    # Start again from the pre-capture control for the next mode.
                    self.control = self.clean['control.lua'].decode('utf-8').replace('\r\n', '\n')
                    self.control += '\nrequire("scripts.se_logistics_verification")\n'

    def test_modified_loaded_runtime_rejected_with_untouched_clean_source(self):
        path = self.production / 'scripts/history.lua'
        path.write_bytes(path.read_bytes() + b'\nreturn {}\n')
        with self.assertRaisesRegex(AssertionError, 'source changed: scripts/history.lua'):
            self.validate()

    def test_unexpected_loaded_file_rejected(self):
        (self.production / 'scripts/unrecorded.lua').write_text('return {}')
        with self.assertRaisesRegex(AssertionError, 'file set changed'):
            self.validate()

    def test_missing_loaded_file_rejected(self):
        (self.production / 'scripts/history.lua').unlink()
        with self.assertRaisesRegex(AssertionError, 'file set changed'):
            self.validate()

    def test_unrecognized_control_injection_rejected(self):
        self.control += '\nrequire("scripts.unrecorded")\n'
        self.write_control()
        with self.assertRaisesRegex(AssertionError, 'control changed'):
            self.validate()

    def test_modified_verification_hook_rejected(self):
        (self.production / 'scripts/se_logistics_verification.lua').write_text('return {}')
        with self.assertRaisesRegex(AssertionError, 'source changed: scripts/se_logistics_verification.lua'):
            self.validate()

    def test_modified_native_helper_rejected(self):
        self.capture(True)
        (self.production / 'scripts/test_locale_native.lua').write_text('return {}')
        with self.assertRaisesRegex(AssertionError, 'source changed: scripts/test_locale_native.lua'):
            self.validate()

    def test_modified_capture_hook_rejected(self):
        self.capture(True)
        (self.production / 'scripts/se_logistics_capture.lua').write_text('return {}')
        with self.assertRaisesRegex(AssertionError, 'source changed: scripts/se_logistics_capture.lua'):
            self.validate()

    def test_gui_hook_hash_must_match_fixture_source(self):
        self.capture(True)
        self.manifest['gui_hook_sha256']['se_logistics_capture.lua'] = '0' * 64
        with self.assertRaisesRegex(AssertionError, 'GUI hook provenance differs'):
            self.validate()


if __name__ == '__main__':
    unittest.main()
