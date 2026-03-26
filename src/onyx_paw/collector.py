import subprocess
from pathlib import Path

_LANG_MAP = {
    ".py": "python", ".js": "javascript", ".ts": "typescript",
    ".go": "go", ".rs": "rust", ".java": "java", ".rb": "ruby",
    ".md": "markdown", ".yaml": "yaml", ".yml": "yaml",
    ".json": "json", ".toml": "toml", ".sql": "sql",
    ".html": "html", ".css": "css", ".sh": "bash",
}
_DOC_EXT = {".md", ".rst", ".txt"}
_CONFIG_EXT = {".yaml", ".yml", ".json", ".toml", ".ini", ".cfg", ".env"}
_BINARY_EXT = {".png", ".jpg", ".gif", ".zip", ".tar", ".gz", ".exe", ".pyc", ".pdf"}
_MAX_SIZE = 1_048_576

def collect_project(path: str, project_type: str) -> list[dict]:
    if project_type == "repo":
        return _collect_git_repo(path)
    return _collect_directory(path)

def _collect_git_repo(path: str) -> list[dict]:
    repo = Path(path)
    result = subprocess.run(["git", "ls-files"], cwd=repo, capture_output=True, text=True)
    if result.returncode != 0:
        return _collect_directory(path)
    docs = []
    for rel in result.stdout.strip().split("\n"):
        if not rel: continue
        full = repo / rel
        if not full.is_file(): continue
        ext = full.suffix.lower()
        if ext in _BINARY_EXT or full.stat().st_size > _MAX_SIZE: continue
        try: content = full.read_text(encoding="utf-8", errors="ignore")
        except Exception: continue
        content = content.replace("\x00", "")
        if not content.strip(): continue
        docs.append({"path": rel, "title": full.name, "type": _classify(rel, ext), "content": content, "language": _LANG_MAP.get(ext)})
    return docs

def _collect_directory(path: str) -> list[dict]:
    root = Path(path)
    docs = []
    for full in root.rglob("*"):
        if not full.is_file(): continue
        ext = full.suffix.lower()
        if ext in _BINARY_EXT or full.stat().st_size > _MAX_SIZE: continue
        try: content = full.read_text(encoding="utf-8", errors="ignore")
        except Exception: continue
        content = content.replace("\x00", "")
        if not content.strip(): continue
        rel = str(full.relative_to(root))
        docs.append({"path": rel, "title": full.name, "type": _classify(rel, ext), "content": content, "language": _LANG_MAP.get(ext)})
    return docs

def _classify(rel_path: str, ext: str) -> str:
    if ext in _DOC_EXT: return "doc"
    if ext in _CONFIG_EXT: return "config"
    if ext == ".sql": return "schema"
    return "source_code"
