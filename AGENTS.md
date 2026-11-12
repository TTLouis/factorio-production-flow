# Production Flow repository hygiene

These rules supplement workspace-level instructions. Build, native-test
and release procedures are maintained in [docs/development.md](docs/development.md).

## Release history

- Edit release notes only in `mod/production-flow/changelog.txt`. It is the
  canonical release history consumed by Factorio and the Mod Portal.
- `CHANGELOG.md` is a generated GitHub-facing view. Run
  `python tools/changelog.py --write` after changing the canonical history; never
  maintain or patch a second set of release bullets there.
- Run `python tools/changelog.py --check` before a build, release commit or push.
  The latest canonical entry must match `mod/production-flow/info.json`.
- Generate a GitHub release's notes with
  `python tools/changelog.py --release VERSION`. Avoid separate hand-maintained
  release-note drafts. The publisher synchronizes new releases' bodies from this
  generated output. Generated drafts belong under ignored output directories.
- Preserve issue links and reporter credit in the canonical entry. Put extended
  engineering notes and benchmark evidence in `docs/validation.md`, linked from
  release history, rather than copying them into every release surface.
- Check the root changelog, packaged changelog, GitHub release notes and Mod
  Portal changelog separately when confirming publication. Verifying one is not
  evidence that all four were updated.
- When work is deferred until a release ships, confirm both GitHub publication
  and Mod Portal availability before applying it. Keep later hygiene commits
  separate from the shipped tag. Never move a published tag, replace a published
  ZIP, or bump/publish another version merely to update repository documentation.

## Ownership and generated files

- Read working-tree and staged status before edits. Preserve unrelated and
  concurrent work; stage explicit paths. Use an isolated worktree when the
  approved release must exclude ongoing changes.
- Keep release version/dependencies in `info.json`; link to metadata instead of
  repeating version labels throughout current documentation. Label historical
  galleries, drafts and measurements clearly.
- `docs/mod-portal.md` owns approved description copy and screenshot references.
  Screenshot-only requests must preserve the live description except image URLs;
  verify that comparison after publishing. Do not create an alternate current
  description or a second current screenshot collection.
- Keep test output, native stages, temporary source copies and draft artifacts
  under ignored output directories. Do not force-add ignored artifacts to make a
  release work. Maintain one current index with links to dated evidence.
- Do not merge independent mod projects' release histories or gameplay code.
  License copies, translated locale catalogs and test fixtures can be intentional;
  retain validation of their contracts rather than removing them blindly.
- Never delete a registered worktree, source save, published archive or validation
  stage solely because it resembles another copy. Check ownership, branch/status,
  hashes and retention needs first. Cleanup requires the user's authorization.

## Proportional verification

- For changelog tooling or publisher changes, run the changelog and publisher
  Python suites. Documentation/tooling changes do not require native game runs,
  a package rebuild or UPS benchmarks unless they affect runtime behavior.
- Native GUI checks default to 1920x1080 at 100% UI scale unless the user explicitly
  requests other sizes/scales. State window resolution and UI scale separately.
- Record which source, archive and screenshots were checked. Keep old evidence
  intact, distinguish historical measurements from new runs, and report material
  validation gaps plainly.
