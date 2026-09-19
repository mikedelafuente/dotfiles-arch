---
description: Link every GitHub issue and PR reference to its GitHub URL
alwaysApply: true
---

Whenever you mention a GitHub issue or pull request, make it a Markdown link to its page
on GitHub, never a bare `#123`: write [#123](https://github.com/<owner>/<repo>/issues/123)
for issues and [#124](https://github.com/<owner>/<repo>/pull/124) for pull requests. Resolve
`<owner>/<repo>` from the current repository (`gh repo view --json nameWithOwner`).

This applies to replies, summaries, and anything you write for people to read, such as
PR descriptions, issue bodies, and comments. In commit messages, keep closing keywords
like `Closes #123` as they are, because GitHub links those itself.
