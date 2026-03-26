import click
from onyx_paw.config import load_config, save_config
from onyx_paw.collector import collect_project
from onyx_paw.sender import send_documents

@click.group()
def cli():
    """Remote Onyx Paw — push local project content to Onyx."""
    pass

@cli.command()
@click.option("--server", required=True, help="Onyx server URL")
@click.option("--key", required=True, help="API key for Onyx")
@click.option("--paw-id", required=True, help="Paw ID (from registration)")
def init(server, key, paw_id):
    config = load_config()
    config["server"] = server
    config["api_key"] = key
    config["paw_id"] = paw_id
    config.setdefault("projects", [])
    save_config(config)
    click.echo(f"Configured to connect to {server}")

@cli.command()
@click.argument("path")
@click.option("--type", "project_type", default="repo")
@click.option("--name", default=None)
@click.option("--schedule", default="0 */2 * * *")
def add(path, project_type, name, schedule):
    config = load_config()
    if not name:
        from pathlib import Path
        name = Path(path).name
    config.setdefault("projects", [])
    config["projects"].append({"path": path, "type": project_type, "name": name, "schedule": schedule})
    save_config(config)
    click.echo(f"Added project '{name}' at {path}")

@cli.command()
def run():
    config = load_config()
    if not config.get("server"):
        click.echo("Not configured. Run: onyx-paw init --server URL --key KEY --paw-id ID")
        return
    for proj in config.get("projects", []):
        click.echo(f"Collecting {proj['name']}...")
        docs = collect_project(proj["path"], proj["type"])
        click.echo(f"  Found {len(docs)} documents, pushing...")
        result = send_documents(config["server"], config["api_key"], config["paw_id"], proj["name"], docs, proj.get("type", "ingest"))
        click.echo(f"  Done: {result}")

@cli.command()
def status():
    config = load_config()
    if not config:
        click.echo("Not configured.")
        return
    click.echo(f"Server: {config.get('server')}")
    click.echo(f"Paw ID: {config.get('paw_id')}")
    click.echo(f"Projects: {len(config.get('projects', []))}")
    for proj in config.get("projects", []):
        click.echo(f"  - {proj['name']} ({proj['path']})")
