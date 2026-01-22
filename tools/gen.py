import os, json, sys, time
from pathlib import Path
from anthropic import Anthropic

SYSTEM_MANIFEST = """You are a senior software engineer.
Return ONLY valid JSON (no markdown, no backticks).

Goal: First, output a MANIFEST only (no full code yet).
Schema:
{
  "project_name": "string",
  "notes": "short",
  "files": [
    {"path": "relative/path", "summary": "1-2 lines about what goes there"}
  ]
}

Rules:
- Paths must be relative (no leading '/'), and must not contain '..'
- Keep the response small and robust. Do NOT include file contents here.
"""

SYSTEM_FILES = """You are a senior software engineer.
Return ONLY valid JSON (no markdown, no backticks).
Schema:
{
  "files": [
    {"path": "relative/path", "content": "file text"}
  ],
  "notes": "optional short notes"
}

Rules:
- Paths must be relative (no leading '/'), and must not contain '..'
- Output ONLY the requested subset of files. No extra files.
- Ensure JSON is valid and complete. Never truncate mid-string.
"""

DEFAULT_MODEL = "claude-sonnet-4-5-20250929"
BATCH_SIZE = 8

def safe_rel_path(p: str) -> str:
    p = (p or "").strip().lstrip("/").replace("\\", "/")
    if not p or ".." in p.split("/"):
        raise ValueError(f"Unsafe path: {p}")
    return p

def parse_json(text: str) -> dict:
    text = (text or "").strip()
    if not text:
        raise SystemExit("Model returned empty response.")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        s = text.find("{")
        e = text.rfind("}")
        if s == -1 or e == -1 or e <= s:
            raise SystemExit("Model did not return valid JSON.\n\nRAW:\n" + text[:2000])
        return json.loads(text[s:e+1])

def write_files(out_root: Path, files: list[dict]) -> None:
    for f in files:
        rel = safe_rel_path(f.get("path"))
        p = out_root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(f.get("content", ""), encoding="utf-8")

def call_model(client: Anthropic, model: str, system: str, user: str, max_tokens: int, dump_path: Path | None = None) -> str:
    msg = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    parts = []
    for part in msg.content:
        t = getattr(part, "text", None)
        if t:
            parts.append(t)
    text = "\n".join(parts).strip()

    if dump_path:
        dump_path.parent.mkdir(parents=True, exist_ok=True)
        dump_path.write_text(text, encoding="utf-8")

    return text

def main():
    api_key = os.getenv("ANTHROPIC_API_KEY")
    model = os.getenv("ANTHROPIC_MODEL", DEFAULT_MODEL)
    if not api_key:
        raise SystemExit("ANTHROPIC_API_KEY not set")

    if len(sys.argv) < 2:
        raise SystemExit('Usage: python tools/gen.py "instruction" --out generated/xxx')

    out_dir = "generated/project"
    args = sys.argv[1:]
    prompt_parts = []
    i = 0
    while i < len(args):
        if args[i] == "--out":
            out_dir = args[i+1]
            i += 2
        else:
            prompt_parts.append(args[i])
            i += 1
    prompt = " ".join(prompt_parts).strip()

    client = Anthropic(api_key=api_key)

    out_root = Path(out_dir).resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    raw_dir = out_root / "_raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    # 1) MANIFEST
    manifest_text = call_model(
        client=client,
        model=model,
        system=SYSTEM_MANIFEST,
        user=prompt,
        max_tokens=2500,
        dump_path=raw_dir / "manifest.txt",
    )
    manifest = parse_json(manifest_text)
    file_specs = manifest.get("files", [])
    if not file_specs:
        raise SystemExit("No files in manifest. RAW:\n" + manifest_text[:2000])

    (out_root / "MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )

    # 2) FILES in batches
    paths = [safe_rel_path(x.get("path")) for x in file_specs if x.get("path")]
    total = len(paths)
    wrote = 0

    for start in range(0, total, BATCH_SIZE):
        batch = paths[start:start+BATCH_SIZE]
        user_req = {
            "instruction": prompt,
            "request": "Generate file contents for the following paths only.",
            "paths": batch
        }

        for attempt in range(2):
            try:
                text = call_model(
                    client=client,
                    model=model,
                    system=SYSTEM_FILES,
                    user=json.dumps(user_req, ensure_ascii=False),
                    max_tokens=7000,
                    dump_path=raw_dir / f"batch_{start}.txt",
                )
                data = parse_json(text)
                files = data.get("files", [])
                if not files:
                    raise ValueError("No files returned for batch: " + str(batch))
                write_files(out_root, files)
                wrote += len(files)
                break
            except Exception as e:
                if attempt == 1:
                    raise
                user_req["request"] = "The previous output was invalid JSON. Return ONLY valid JSON for these paths. No markdown. Ensure all strings are closed."
                time.sleep(0.5)

    print(f"✅ manifest {total} files | wrote {wrote} files -> {out_root}")

if __name__ == "__main__":
    main()
