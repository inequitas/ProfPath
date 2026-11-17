# Security Policy

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue.

Use GitHub's private vulnerability reporting: go to the [Security tab](https://github.com/inequitas/ProfPath/security) and click **Report a vulnerability**. That opens a private thread visible only to you and the maintainer.

Please include what you found, how to reproduce it, and which version you were running (`/pp about` in game shows it).

## What to expect

This is a free project maintained by one person in their spare time, so please calibrate accordingly:

- I aim to acknowledge a report within a few days.
- If it is confirmed, a fix goes out in the next release, or sooner as a patch release if it warrants one.
- I will credit you in the changelog unless you would rather stay anonymous.

## Supported versions

Only the latest release is supported. Fixes are not backported; if you are behind, updating is the fix.

## Scope

ProfPath is a World of Warcraft addon. It runs inside the game's Lua sandbox, uses only the game's addon API, and makes no network calls of its own. What is in scope:

- **Saved data.** ProfPath stores prices, trainer and recipe information in its SavedVariables file. Anything in that data that could make the addon misbehave in a way another player or addon could trigger is worth reporting.
- **The development scripts** in `tools/` (data download, packaging). They run on a developer's machine, so anything that makes them execute something unexpected is in scope.

## Out of scope

- **The game's own addon restrictions.** ProfPath cannot buy, post or craft on its own; the game requires a player's click for those, and ProfPath does not try to get around that.
- **Automated scanner output with no demonstrated impact.** A finding that cannot be tied to something an attacker could actually do is not actionable on a project this size.
