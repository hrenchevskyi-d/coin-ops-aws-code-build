# Release Automation

`release-please` manages semantic repository releases from Conventional Commit style PR titles and squash merge commit titles.

## Branch Model

- `dev`: integration branch.
- `main`: stable release branch.
- `Shabat`: still publishes `shabat-latest` for deployment images.
- tags `vX.Y.Z`: publish immutable release images.

The only image currently built from this repository is `coin-ops-postgres-runtime`. Application images are external GHCR inputs.

## Maintainer Flow

1. Merge normal work into `dev`.
2. Promote approved work to `main`.
3. `release-please` opens or updates a release PR.
4. Merge the release PR.
5. The workflow creates the release tag and dispatches the infra image workflow for that tag.

## Version Bumps

- `fix: ...` -> patch
- `feat: ...` -> minor
- `feat!: ...`, `fix!: ...`, or `BREAKING CHANGE:` footer -> major

Docs, chore, and CI-only changes can appear in changelogs but do not need to trigger a version bump unless they change operator behavior.
