# Release writing guide

Write for players. Say what they can do, what works better, and what they need
to know. Keep implementation details and extended explanations on GitHub.

## Update notes

- Lead with the most useful changes and fixes.
- Aim for 3–6 short bullets for a typical update; use fewer for a small release.
- Give each bullet one clear point. Combine related UI adjustments.
- Describe the result the player sees, rather than every change made to achieve it.
- Include compatibility changes, changed defaults or required actions when they
  affect players. Keep the explanation brief.
- Skip pixel measurements, internal names, code structure, test counts, benchmark
  methods and development-tool cleanup unless they affect how someone uses the mod.
- Do not turn the notes into a development diary or repeat the full mod description.

Example player-facing notes:

- Choose items and fluids from one searchable selector.
- Return to recently viewed materials with Focus history and Back/Forward.
- Balance keeps your place when you inspect an item.
- Cleaner table headings and clearer scrolling boundaries.
- Adjust how often chest stock refreshes in mod settings.

## Mod descriptions

- Open with what the mod helps the player do, in one or two sentences.
- Follow with a short list of its main uses. Focus on the experience, not an
  inventory of controls or everything added in the latest version.
- Use a few current screenshots to show the UI. Avoid explaining every visible
  button, margin or heading in the surrounding text.
- Keep installation requirements and important limitations easy to find.
- Mention unfinished areas plainly and briefly. Do not repeat the same caveat.
- Put detailed calculations, sampling rules and technical explanations on GitHub.
  A single link is enough when that detail would help interested players.

Example opening:

> See what your factory makes and uses, spot production imbalances, and explore
> the recipes connecting items and fluids.

## GitHub detail

GitHub release notes and documentation may include fuller change lists,
calculation details, test evidence, performance measurements and implementation
notes. Keep the short player-facing summary first. The Mod Portal description
and packaged changelog should stand on their own without those details.

## Final edit

For each sentence, ask: does this help a player understand the mod, notice an
improvement, or know what to do? If not, remove it or move it to GitHub.
Be specific and accurate, but stop once the point is clear.
