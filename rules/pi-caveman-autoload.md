---
description: Auto-load the caveman skill at pi startup
alwaysApply: true
---

At pi startup, read and follow the caveman skill immediately, before any task:

- `~/.pi/agent/skills/caveman/SKILL.md`

Follow its full default (`full`) level from the first response. Persist until the
user says "stop caveman" or "normal mode".