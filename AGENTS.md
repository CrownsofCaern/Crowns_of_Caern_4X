# Agent entry point

Read [CLAUDE.md](CLAUDE.md) for the project's rules and test commands; they apply to all contributors and agents. Use [docs/REPOSITORY_GUIDE.md](docs/REPOSITORY_GUIDE.md) to find the relevant code, data, tests and artwork before making changes. Read [docs/DESIGN.md](docs/DESIGN.md) for design and architecture and [docs/ART_BIBLE.md](docs/ART_BIBLE.md) for visual work.

Preserve unrelated changes in the working tree. Game logic must remain deterministic and headless; route changes to game state through `GameSession`. Treat source art and generated outputs as build inputs and outputs, respectively: check the asset pipeline and its references before deleting or moving either. Keep save migration and historical identifiers intact unless explicitly migrating them.
