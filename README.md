# Onyx Paw

Lightweight agent that pushes local project content to your [Onyx](https://github.com/WebWalker3D/Onyx) server for search and indexing.

## Quick Install

```bash
git clone https://github.com/WebWalker3D/Onyx-Paw.git
cd Onyx-Paw
bash install.sh
```

The installer will prompt you for:
- Your Onyx server URL
- Your API key
- Projects to index
- Optional cron schedule for automatic syncing

## Requirements

- Python 3.10+
- pip
- curl

## Commands

After installation:

```bash
onyx-paw status       # Show config and registered projects
onyx-paw add <path>   # Register a project to index
onyx-paw run          # Push all projects to Onyx now
```

## Configuration

Config is stored at `~/.onyx-paw.yaml`. Edit it directly to change project paths, names, schedules, or connection settings.

## License

MIT
