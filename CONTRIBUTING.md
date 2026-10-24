# Contributing

Describe the problem and expected behavior before proposing a large change.
Run `python tests/run_lua.py` for code changes. For GUI changes, follow the
vanilla style rules in [docs/ui-style.md](docs/ui-style.md) and also inspect
native Factorio screenshots at relevant GUI scales. Mock checks do not establish
pixel-level layout correctness.

Use copied saves and an isolated mod/config directory for native tests. Keep
save files, local exports, credentials and generated test output out of commits.
Use existing Lua module conventions: require modules at file scope and avoid
GUI element names that collide with LuaGuiElement properties.

Contributions are made under the project's MIT license.
