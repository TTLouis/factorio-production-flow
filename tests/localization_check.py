"""Validate Factorio locale catalogs and literal runtime references, offline."""
from dataclasses import dataclass
from collections import Counter
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mod/production-flow"
PARAMETER = re.compile(r"__(\d+)__|__plural_for_parameter__(\d+)__")
TOKEN = re.compile(
    r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|'
    r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|'
    r'[A-Za-z_][A-Za-z_0-9]*|\.\.\.|\.\.|==|~=|<=|>=|[^\s]', re.S)


@dataclass(frozen=True)
class Token:
    text: str
    line: int

    @property
    def string(self):
        return self.text.startswith(('"', "'")) or bool(re.match(r"\[=*\[", self.text))

    @property
    def value(self):
        if self.text.startswith("["):
            opening = re.match(r"\[(=*)\[", self.text)
            size = len(opening[0])
            return self.text[size:-size].removeprefix("\n")
        return re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "\r", "t": "\t"}.get(m[1], m[1]), self.text[1:-1])


def tokens(source):
    return [Token(m[0], source.count("\n", 0, m.start()) + 1)
            for m in TOKEN.finditer(source) if not m[0].startswith("--")]


def parameters(value):
    return {int(a or b) for a, b in PARAMETER.findall(value)}


def rich_text_tags(value):
    return Counter(re.findall(
        r'\[(?:/?(?:color|font)|img|item|fluid|recipe|entity|planet|technology|space-location)(?:=[^\]]*)?\]', value))


def read_catalog(path):
    entries, section = {}, None
    for line, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        text = raw.strip()
        if not text or text.startswith(("#", ";")):
            continue
        if text.startswith("[") and text.endswith("]"):
            section = text[1:-1]
            continue
        if "=" not in raw or section is None:
            raise ValueError(f"{path}:{line}: expected [section] or key=value")
        name, value = raw.split("=", 1)
        key = section + "." + name.strip()
        if key in entries:
            raise ValueError(f"{path}:{line}: duplicate locale key {key}")
        if not value.strip():
            raise ValueError(f"{path}:{line}: empty locale value {key}")
        value = value.replace(r"\n", "\n")
        plural_count = len(re.findall(r"__plural_for_parameter__\d+__\{[^}]+\}__", value))
        if value.count("__plural_for_parameter") != plural_count:
            raise ValueError(f"{path}:{line}: malformed native plural expression in {key}")
        used = parameters(value)
        if used and (min(used) < 1 or max(used) > 20 or used != set(range(1, max(used) + 1))):
            raise ValueError(f"{path}:{line}: invalid parameter sequence in {key}: {sorted(used)}")
        entries[key] = value
    return entries


def arguments(stream, opening):
    """Split a call/table at top-level commas, including nested LocalisedStrings."""
    pairs = {"(": ")", "{": "}", "[": "]"}
    stack, result, start = [pairs[stream[opening].text]], [], opening + 1
    for i in range(start, len(stream)):
        text = stream[i].text
        if text in pairs:
            stack.append(pairs[text])
        elif text == stack[-1]:
            stack.pop()
            if not stack:
                if i > start:
                    result.append(stream[start:i])
                return result
        elif text == "," and len(stack) == 1:
            result.append(stream[start:i])
            start = i + 1
    raise ValueError("unclosed locale expression")


def source_errors(source, catalog, name="source"):
    stream, errors = tokens(source), []
    for i, token in enumerate(stream):
        if token.text == "Loc" and i + 1 < len(stream) and stream[i + 1].text == "(":
            args = arguments(stream, i + 1)
            key_tokens = args[0] if args else []
            if len(key_tokens) == 1 and key_tokens[0].string:
                keys = ["production-flow." + key_tokens[0].value]
            else:
                keys = ["production-flow." + t.value for j, t in enumerate(key_tokens)
                        if t.string and j and key_tokens[j - 1].text in ("and", "or")]
            if not keys:
                errors.append(f"{name}:{token.line}: locale key must be literal (or literal conditional alternatives)")
            count = len(args) - 1
        elif (token.string and token.value.startswith("production-flow.") and i
              and stream[i - 1].text == "{" and stream[i + 1].text in (",", "}")):
            args = arguments(stream, i - 1)
            keys, count = [token.value], len(args) - 1
        else:
            continue
        for key in keys:
            if key not in catalog:
                errors.append(f"{name}:{token.line}: missing English locale key {key}")
            elif count != len(parameters(catalog[key])):
                errors.append(f"{name}:{token.line}: {key} expects {len(parameters(catalog[key]))} parameters, got {count}")
    return errors


def raw_text_errors(source, name="source"):
    """Catch prose accidentally reintroduced into shipped Lua, including helpers.

    This is a conservative guard for English prose, not a Lua type checker. IDs,
    patterns, format specifiers, rich-text markup and user/prototype names remain
    data. Native tests cover messages composed from dynamic values.
    """
    errors = []
    for token in tokens(source):
        if not token.string:
            continue
        value = token.value
        if value in ("items/s", "fluid/s", "crafts/s", "/s"):
            errors.append(f"{name}:{token.line}: unit needs a locale key: {value!r}")
            continue
        if value.startswith(("ssk-", "utility/", "scripts.", "shared.", "item/", "fluid/", "recipe/", "fluid:", "sub:", "super:", "roots:")):
            continue
        if "^" in value:
            continue
        visible = re.sub(r'%%|%[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGqs]', '', value)
        visible = re.sub(r"\[[^\]]*\]", "", visible)
        if re.search(r"[A-Z]|[a-z][ ,:;\n][a-zA-Z]", visible):
            errors.append(f"{name}:{token.line}: player-facing literal needs a locale key: {value!r}")
    return errors


def validate(mod=MOD):
    errors, catalogs = [], {}
    for folder in sorted((mod / "locale").iterdir()):
        if not folder.is_dir():
            continue
        entries = {}
        for path in sorted(folder.glob("*.cfg")):
            try:
                incoming = read_catalog(path)
                duplicate = entries.keys() & incoming.keys()
                if duplicate:
                    raise ValueError(f"{path}: duplicate keys across locale files: {sorted(duplicate)}")
                entries.update(incoming)
            except ValueError as exc:
                errors.append(str(exc))
        catalogs[folder.name] = entries
    english = catalogs.get("en", {})
    if not english:
        errors.append("Missing English locale catalog")
    for language, entries in catalogs.items():
        if language == "en":
            continue
        for key in english.keys() - entries.keys():
            errors.append(f"{language}: missing locale key {key}")
        for key in entries:
            if key not in english:
                errors.append(f"{language}: unknown locale key {key}")
            elif parameters(entries[key]) != parameters(english[key]):
                errors.append(f"{language}: parameter mismatch for {key}")
            elif rich_text_tags(entries[key]) != rich_text_tags(english[key]):
                errors.append(f"{language}: rich-text tag mismatch for {key}")
    for path in sorted(mod.rglob("*.lua")):
        if "tools" not in path.relative_to(mod).parts:
            source = path.read_text(encoding="utf-8")
            errors.extend(source_errors(source, english, str(path.relative_to(mod))))
            errors.extend(raw_text_errors(source, str(path.relative_to(mod))))
    settings = (mod / "settings.lua").read_text(encoding="utf-8")
    for name in re.findall(r'name\s*=\s*"(ssk-[^"]+)"', settings):
        for section in ["mod-setting-name", "mod-setting-description"]:
            if section + "." + name not in english:
                errors.append(f"settings.lua: missing {section}.{name}")
    if errors:
        raise ValueError("Localization validation failed:\n" + "\n".join(errors))
    return english, len(catalogs)


def install_native_support(target, language="en"):
    """Inject only into private native-test copies, after clean packaging."""
    catalog, _ = validate()
    language_folder = MOD / "locale" / language
    if language_folder not in list((MOD / "locale").iterdir()) or not language_folder.is_dir():
        raise ValueError(f"Unknown shipped locale: {language}")
    translated = {}
    for path in sorted(language_folder.glob("*.cfg")):
        translated.update(read_catalog(path))
    quoted = lambda value: json.dumps(value, ensure_ascii=False)
    resolver = (ROOT / "tests/locale_test_support.lua").read_text(encoding="utf-8")
    # Existing behavioural assertions resolve English independently of the
    # language rendered by the client and checked by the translation probes.
    for filename, entries in [("test_locale.lua", catalog), ("test_locale_target.lua", translated)]:
        values = ",\n".join(f"[{quoted(k)}]={quoted(v)}" for k, v in entries.items())
        (target / "scripts" / filename).write_text(
            "local factory = (function()\n" + resolver + "\nend)()\nreturn factory({\n" + values + "\n})\n", encoding="utf-8")
    (target / "scripts/test_locale_language.lua").write_text("return " + quoted(language) + "\n", encoding="utf-8")
    probes = []
    for key, value in sorted(catalog.items()):
        count = len(parameters(value))
        for n in ([0, 1, 2] if "__plural_for_parameter_" in value else [2]):
            probes.append("{" + ",".join([quoted(key), *[quoted(str(n)) for _ in range(count)]]) + "}")
    (target / "scripts/test_locale_probes.lua").write_text(
        "return {\n" + ",\n".join(probes) + "\n}\n", encoding="utf-8")
    (target / "scripts/test_locale_native.lua").write_text(
        (ROOT / "tests/localization_native.lua").read_text(encoding="utf-8"), encoding="utf-8")


if __name__ == "__main__":
    catalog, count = validate()
    print(f"LOCALIZATION OK: {len(catalog)} English keys; {count} language(s); references and parameters checked")
