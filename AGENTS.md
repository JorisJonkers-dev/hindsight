# Agents

Guidance for any coding agent working in this repository. It holds the estate's Hindsight api, control plane and text-embeddings-inference images, delivered as the Project hindsight.

The repo's agent contract is [CLAUDE.md](CLAUDE.md); the estate-wide conventions are at https://github.com/JorisJonkers-dev/workspace/blob/main/CLAUDE.md.

## Build and test

- Lint shell: `shellcheck api/hindsight-start control-plane/control-plane-start scripts/*.sh`
- Build the three images from `api`, `control-plane` and `tei`, then run `scripts/smoke-test.sh hindsight:ci hindsight-control-plane:ci hindsight-tei:ci`
- Lint workflows: `actionlint .github/workflows/*.yml`
