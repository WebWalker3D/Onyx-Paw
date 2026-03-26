import httpx

def send_documents(server_url: str, api_key: str, paw_id: str, project_name: str, documents: list[dict], project_type: str = "ingest"):
    url = f"{server_url.rstrip('/')}/api/ingest"
    resp = httpx.post(url, headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={"paw_id": paw_id, "project_name": project_name, "project_type": project_type, "documents": documents}, timeout=120.0)
    if resp.status_code >= 400:
        raise RuntimeError(f"{resp.status_code} from {url}: {resp.text}")
    return resp.json()
