---
description: What "merge this" means as a shorthand for the full branch → PR → merge workflow
alwaysApply: true
---

When I say "merge this" (or an equivalent like "ship this", "let's merge"), treat it as
shorthand for the whole workflow, not a literal `git merge`:

1. If the current branch is `main` (or otherwise not already a feature branch), create a
   new branch first — never commit directly to `main`.
2. Commit the pending changes.
3. Push the branch to the remote.
4. Open a pull request.
5. Merge the pull request.

After the merge, follow the usual cleanup: delete both the local and remote branch and
check out `main`.

Still confirm before any destructive or hard-to-reverse step (force-push, skipping hooks,
etc.) per standard git safety practice — this shorthand covers *what* the request means,
not a license to skip normal confirmation.
