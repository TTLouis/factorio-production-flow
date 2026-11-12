"""Regression tests for locale validation failures and Lua lexical boundaries."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from localization_check import MOD, install_native_support, parameters, raw_text_errors, read_catalog, source_errors, validate

OUT = Path(__file__).resolve().parent / 'out/localization-fixtures'
OUT.mkdir(parents=True, exist_ok=True)


class LocalizationTests(unittest.TestCase):
    def catalog(self, text):
        with tempfile.TemporaryDirectory(dir=OUT) as directory:
            assert Path(directory).resolve().is_relative_to(OUT.resolve())
            path = Path(directory) / "locale.cfg"
            path.write_text(text, encoding="utf-8")
            return read_catalog(path)

    def test_repository(self):
        english, languages = validate()
        self.assertIn('production-flow.ui-recorded', english)
        self.assertGreaterEqual(languages, 1)

    def test_missing_and_misspelled_keys(self):
        self.assertIn("missing English", source_errors('Loc("missing")', {})[0])
        self.assertIn("missing English", source_errors('{"production-flow.missing"}', {})[0])

    def test_call_parameter_count(self):
        catalog = {"production-flow.message": "__1__ and __2__"}
        self.assertIn("got 1", source_errors('Loc("message", value)', catalog)[0])
        self.assertIn("got 3", source_errors('Loc("message", 1, 2, 3)', catalog)[0])
        self.assertFalse(source_errors('Loc("message", {"", a, b}, format(1, 2))', catalog))

    def test_nested_and_conditional_references(self):
        catalog = {"production-flow.outer": "__1__", "production-flow.inner": "Inner",
                   "production-flow.a": "__1__", "production-flow.b": "__1__"}
        self.assertFalse(source_errors('Loc("outer", Loc("inner"))', catalog))
        self.assertFalse(source_errors('Loc(kind == "fluid" and "a" or "b", value)', catalog))
        self.assertIn("missing English", source_errors('Loc(flag and "a" or "typo", value)', catalog)[0])
        self.assertTrue(source_errors('Loc(variable, value)', catalog))

    def test_comments_and_escaped_quotes(self):
        self.assertFalse(source_errors('-- Loc("missing")\n--[[ Loc("missing") ]]', {}))
        self.assertFalse(raw_text_errors('-- "Ignored prose"\nlocal pattern="^(%a+)/"'))
        self.assertTrue(raw_text_errors('caption="Choose \\"a\\" material"'))
        self.assertTrue(raw_text_errors('caption=[=[Choose a material]=]'))

    def test_raw_player_text(self):
        self.assertTrue(raw_text_errors('tooltip="Refresh the chart"'))
        self.assertTrue(raw_text_errors('caption="Net %"'))
        self.assertTrue(raw_text_errors('unit="fluid/s"'))
        self.assertTrue(raw_text_errors('unit="/s"'))
        self.assertFalse(raw_text_errors('sprite="utility/search"; id="ssk-main"; key="fluid:water"'))

    def test_duplicate_keys(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.catalog('[production-flow]\na=First\na=Second\n')

    def test_invalid_catalog(self):
        for text in ['a=Outside section', '[production-flow]\na=', '[production-flow]\na=__0__',
                     '[production-flow]\na=__2__', '[production-flow]\na=__21__',
                     '[production-flow]\na=__1__ __plural_for_parameter_1_{1=item|rest=items}__']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.catalog(text)

    def test_reordered_parameters_and_native_plurals(self):
        entries = self.catalog('[production-flow]\na=__2__: __1__\nb=__1__ __plural_for_parameter__1__{1=item|rest=items}__')
        self.assertEqual(parameters(entries['production-flow.a']), {1, 2})
        self.assertEqual(parameters(entries['production-flow.b']), {1})

    def test_translation_coverage_and_parameters(self):
        with tempfile.TemporaryDirectory(dir=OUT) as directory:
            assert Path(directory).resolve().is_relative_to(OUT.resolve())
            mod = Path(directory)
            for lang in ['en', 'fr']:
                (mod / 'locale' / lang).mkdir(parents=True)
            (mod / 'settings.lua').write_text('')
            (mod / 'locale/en/locale.cfg').write_text('[production-flow]\na=Hello __1__\nb=World')
            translation = mod / 'locale/fr/locale.cfg'
            translation.write_text('[production-flow]\na=Bonjour')
            with self.assertRaisesRegex(ValueError, 'missing locale key'):
                validate(mod)
            translation.write_text('[production-flow]\na=Bonjour\nb=Monde')
            with self.assertRaisesRegex(ValueError, 'parameter mismatch'):
                validate(mod)
            translation.write_text('[production-flow]\na=Bonjour __1__\nb=Monde\nc=Extra')
            with self.assertRaisesRegex(ValueError, 'unknown locale key'):
                validate(mod)
            translation.write_text('[production-flow]\na=Bonjour __1__\nb=Monde')
            validate(mod)

    def test_translation_preserves_functional_rich_text(self):
        with tempfile.TemporaryDirectory(dir=OUT) as directory:
            assert Path(directory).resolve().is_relative_to(OUT.resolve())
            mod = Path(directory)
            for lang in ['en', 'zh-CN']:
                (mod / 'locale' / lang).mkdir(parents=True)
            (mod / 'settings.lua').write_text('')
            (mod / 'locale/en/locale.cfg').write_text('[production-flow]\na=[color=red]Value __1__[/color]')
            translation = mod / 'locale/zh-CN/locale.cfg'
            translation.write_text('[production-flow]\na=[color=blue]数值 __1__[/color]', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'rich-text tag mismatch'):
                validate(mod)
            translation.write_text('[production-flow]\na=[color=red]数值 __1__[/color]', encoding='utf-8')
            validate(mod)

    def test_native_support_keeps_assertion_and_render_languages_separate(self):
        with tempfile.TemporaryDirectory(dir=OUT) as directory:
            assert Path(directory).resolve().is_relative_to(OUT.resolve())
            mod = Path(directory) / 'source'
            for language, text in [('en', 'Recorded __1__'), ('zh-CN', '已记录 __1__')]:
                folder = mod / 'locale' / language
                folder.mkdir(parents=True)
                (folder / 'locale.cfg').write_text('[production-flow]\na=' + text, encoding='utf-8')
            target = Path(directory) / 'target'
            (target / 'scripts').mkdir(parents=True)
            with patch('localization_check.MOD', mod), patch('localization_check.validate', return_value=({'production-flow.a': 'Recorded __1__'}, 2)):
                install_native_support(target, 'zh-CN')
                with self.assertRaisesRegex(ValueError, 'Unknown shipped locale'):
                    install_native_support(target, '../not-a-locale')
            self.assertIn('Recorded __1__', (target / 'scripts/test_locale.lua').read_text(encoding='utf-8'))
            self.assertIn('已记录 __1__', (target / 'scripts/test_locale_target.lua').read_text(encoding='utf-8'))
            self.assertEqual((target / 'scripts/test_locale_language.lua').read_text(), 'return "zh-CN"\n')

    def test_simplified_chinese_rate_units_and_terminology(self):
        chinese = read_catalog(MOD / 'locale/zh-CN/locale.cfg')
        self.assertFalse(any('/s' in value or '/min' in value for value in chinese.values()))
        for key, term in [('unit-fluid-rate', '流体/秒'), ('rate-per-second', '__1__/秒'),
                          ('groups-default-vulcanus', '祝融星'), ('groups-default-fulgora', '雷神星'),
                          ('groups-default-gleba', '句芒星'), ('groups-default-aquilo', '玄冥星'),
                          ('history-labs-estimated', '研究中心（估算）')]:
            self.assertEqual(chinese['production-flow.' + key], term)


if __name__ == '__main__':
    unittest.main()
