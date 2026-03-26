from pathlib import Path
import yaml

CONFIG_PATH = Path.home() / ".onyx-paw.yaml"

def load_config() -> dict:
    if not CONFIG_PATH.exists():
        return {}
    return yaml.safe_load(CONFIG_PATH.read_text()) or {}

def save_config(config: dict):
    CONFIG_PATH.write_text(yaml.dump(config, default_flow_style=False))
