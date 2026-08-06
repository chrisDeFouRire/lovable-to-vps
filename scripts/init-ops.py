#!/usr/bin/env python3
import argparse
import re
from pathlib import Path

REQUIRED = {
    "APP_SLUG", "APP_NAME", "BASE_DOMAIN", "SSH_HOST", "SSH_USER",
    "GITHUB_REPO", "STAGING_BRANCH", "PRODUCTION_BRANCH", "DATA_ROOT",
    "SUPABASE_REF", "STAGING_KONG_HTTP_PORT", "STAGING_KONG_HTTPS_PORT",
    "STAGING_POSTGRES_PORT", "STAGING_POOLER_PORT",
    "PRODUCTION_KONG_HTTP_PORT", "PRODUCTION_KONG_HTTPS_PORT",
    "PRODUCTION_POSTGRES_PORT", "PRODUCTION_POOLER_PORT",
}

def read_config(path: Path) -> dict[str, str]:
    values = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise SystemExit(f"invalid config line: {raw}")
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    missing = REQUIRED - values.keys()
    if missing:
        raise SystemExit("missing config keys: " + ", ".join(sorted(missing)))
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", values["APP_SLUG"]):
        raise SystemExit("APP_SLUG must contain lowercase letters, numbers, and hyphens")
    return values

def render(src: Path, dst: Path, values: dict[str, str], executable=False):
    text = src.read_text()
    for key, value in values.items():
        text = text.replace("{{" + key + "}}", value)
    leftovers = sorted(set(re.findall(r"{{([A-Z0-9_]+)}}", text)))
    if leftovers:
        raise SystemExit(f"unresolved placeholders in {src}: {', '.join(leftovers)}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(text)
    if executable:
        dst.chmod(0o755)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True, type=Path)
    ap.add_argument("--repo", required=True, type=Path)
    args = ap.parse_args()
    values = read_config(args.config)
    root = Path(__file__).resolve().parent.parent
    templates = root / "assets/templates"
    repo = args.repo.resolve()
    if not (repo / ".git").exists():
        raise SystemExit(f"not a Git repository: {repo}")

    render(templates / ".env.example", repo / ".env.example", values)
    render(templates / "ops/ops.md", repo / "ops/ops.md", values)
    render(templates / "ops/TODO.md", repo / "ops/TODO.md", values)
    render(templates / "ops/docker/daemon.json", repo / "ops/docker/daemon.json", values)
    render(templates / "ops/Caddyfile", repo / "ops/Caddyfile", values)

    for env in ("staging", "production"):
        prefix = env.upper()
        host = "staging" if env == "staging" else "prod"
        env_values = values | {
            "ENVIRONMENT": env,
            "APP_HOST": f"{host}.{values['BASE_DOMAIN']}",
            "SUPABASE_HOST": f"supabase-{host}.{values['BASE_DOMAIN']}",
            "KONG_HTTP_PORT": values[f"{prefix}_KONG_HTTP_PORT"],
        }
        render(templates / "ops/environment/backup/supabase-db-backup", repo / f"ops/{env}/backup/supabase-db-backup", env_values, True)
        marker = repo / f"ops/{env}/supabase/.app-migrations"
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.touch(exist_ok=True)
        (marker.parent / ".supabase-version").write_text(values["SUPABASE_REF"] + "\n")

    gitignore = repo / ".gitignore"
    existing = gitignore.read_text() if gitignore.exists() else ""
    additions = [x for x in (".env", "*.local") if not any(line.strip() == x for line in existing.splitlines())]
    if additions:
        gitignore.write_text(existing.rstrip() + "\n" + "\n".join(additions) + "\n")
    print(f"Generated non-secret operations scaffold in {repo / 'ops'}")
    print("Next: audit and review every generated file before committing.")

if __name__ == "__main__":
    main()
