# Media organization UX revision

Daniel's current priorities override the earlier shortcut and confirmation plan:

- Keys 1–5 rate the current image or video in gallery and slideshow/viewer.
- Rating, sorting and tagging stay accessible in both contexts.
- Copy/move commands do not ask an extra confirmation question. Planned paths,
  collision checks, verified transfers and durable recovery remain.
- Deletion confirmation is optional, defaults on, and clearly distinguishes
  permanent deletion from recoverable Trash.
- Reduce the bulky toolbar and repeated instructions. Keep stars, Sort and Tags
  together, with advanced tools in a secondary menu. Preserve visible selection,
  queued-action state, optional labels, touch targets and keyboard access.

Guidance located with omgskills, read at verified pinned revisions:

- [Design critique](https://github.com/cuellarfr/design-skills/blob/7e25e66e87f64f9d3dea22198f9e29937e7c48f5/skills/design-critique/SKILL.md)
  for task hierarchy, consistent actions and removing unnecessary interaction.
- [Android mobile design](https://github.com/wshobson/agents/tree/0874a27b17a22e2b7c2e2bcd725768e0803cad06)
  for adaptive tablet layouts, themes and accessible touch targets. Apply its
  interaction guidance to the existing Flutter app; do not change UI frameworks.
- [ADHD design reference](https://github.com/curiositech/some_claude_skills/blob/f49825290077e5fb46bb3e867dfa8a5b0161152b/.claude/skills/adhd-design-expert/SKILL.md)
  for visible state, consistent placement, easy resumption and lower friction.
  Its clinical generalizations and gamification suggestions are not requirements;
  this app adds no diagnosis, streaks, rewards, forced timers or AI dependencies.

These are design references, not a substitute for Daniel's feedback or hardware
usability testing. New key bindings and flows must be covered by regression tests
and reflected in the help/cheat sheet before distribution.
