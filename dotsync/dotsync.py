#!/usr/bin/env python3
"""dotsync: GitHub'daki kişisel ayar repo'sunu yerelle karşılaştırır, eksikleri kurar.

Güvenlik modeli
  * Açılışta çalışan `boot` yalnızca VERİ okur (manifest + dosya varlığı + paket sorgusu).
    Manifestten gelen hiçbir komut kullanıcı onayı olmadan çalıştırılmaz.
  * Denetimler (`check`) bildirimsel: exists / file_lacks. Kabuk komutu yok.
  * Dosya kurulumu yalnızca YEREL OLARAK OLMAYAN dosyaları kopyalar, varsa dokunmaz.
  * Bu istemci repo'dan otomatik güncellenmez (bootstrap ile bir kez kurulur).

Komutlar: status [--sync] [--include-declined] | apply ID... [--decline ID...] | decline ID... | reset | sync | boot | setup
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Iterable

DEFAULT_REPO = "KaanAlper/kaan-dots"
KINDS = {"files", "pkgs", "check"}
SYNC_TIMEOUT_S = 20
CLONE_TIMEOUT_S = 90


class ManifestError(Exception):
    """manifest.json geçersiz ya da güvensiz yol içeriyor."""


# ----------------------------------------------------------------------------- paths


def _xdg(env: str, fallback: str) -> Path:
    return Path(os.environ.get(env) or Path.home() / fallback)


def data_dir() -> Path:
    return _xdg("XDG_DATA_HOME", ".local/share") / "dotsync"


def state_dir() -> Path:
    return _xdg("XDG_STATE_HOME", ".local/state") / "dotsync"


def repo_dir() -> Path:
    return data_dir() / "repo"


def repo_name() -> str:
    env = os.environ.get("DOTSYNC_REPO")
    if env:
        return env
    cfg = _xdg("XDG_CONFIG_HOME", ".config") / "dotsync" / "config.json"
    try:
        return str(json.loads(cfg.read_text(encoding="utf-8")).get("repo", DEFAULT_REPO))
    except (OSError, ValueError):
        return DEFAULT_REPO


def expand(path: str) -> Path:
    return Path(os.path.expanduser(path))


# ----------------------------------------------------------------------------- manifest


def _safe_rel(rel: str, what: str) -> None:
    p = Path(rel)
    if p.is_absolute() or ".." in p.parts:
        raise ManifestError(f"{what}: güvensiz yol {rel!r}")


def load_manifest(repo: Path) -> dict:
    try:
        manifest = json.loads((repo / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ManifestError(f"manifest.json okunamadı: {exc}") from exc
    if manifest.get("schema") != 1 or not isinstance(manifest.get("items"), list):
        raise ManifestError("manifest.json: schema 1 ve items listesi bekleniyor")
    seen: set[str] = set()
    for item in manifest["items"]:
        iid = item.get("id")
        if not iid or iid in seen or item.get("kind") not in KINDS:
            raise ManifestError(f"geçersiz ya da yinelenen öğe: {iid!r}")
        seen.add(iid)
        if item["kind"] == "files":
            _safe_rel(item.get("src", ""), f"{iid}.src")
            if not item.get("dest"):
                raise ManifestError(f"{iid}: dest eksik")
            for rel in item.get("executable", []):
                _safe_rel(rel, f"{iid}.executable")
    return manifest


# ----------------------------------------------------------------------------- state


def _file_pairs(item: dict, repo: Path) -> list[tuple[str, Path, Path]]:
    """(göreli yol, repo'daki dosya, yereldeki hedef). Sembolik bağlar atlanır."""
    src_root = repo / item["src"]
    dest_root = expand(item["dest"])
    pairs = []
    for dirpath, _dirs, files in os.walk(src_root):
        for name in sorted(files):
            src = Path(dirpath) / name
            if src.is_symlink():
                continue
            rel = src.relative_to(src_root).as_posix()
            pairs.append((rel, src, dest_root / rel))
    return sorted(pairs)


def _pacman_has(pkg: str) -> bool:
    return subprocess.run(
        ["pacman", "-Q", pkg], capture_output=True, check=False
    ).returncode == 0


def _failed_conditions(conds: Iterable[dict]) -> list[str]:
    failed = []
    for cond in conds:
        if "exists" in cond and not os.path.exists(expand(cond["exists"])):
            failed.append(f"yok: {cond['exists']}")
        elif "file_lacks" in cond:
            path, needle = cond["file_lacks"]
            try:
                text = expand(path).read_text(encoding="utf-8", errors="replace")
            except OSError:
                failed.append(f"okunamadı: {path}")
                continue
            if needle in text:
                failed.append(f"{path} içinde '{needle}' var")
    return failed


def _missing(item: dict, repo: Path, is_pkg_installed: Callable[[str], bool]) -> list[str]:
    kind = item["kind"]
    if kind == "files":
        return [rel for rel, _src, dest in _file_pairs(item, repo) if not os.path.lexists(dest)]
    if kind == "pkgs":
        return [p for p in item["pkgs"] if not is_pkg_installed(p)]
    return _failed_conditions(item.get("check", []))


def compute_status(
    manifest: dict,
    repo: Path,
    declined: set[str],
    is_pkg_installed: Callable[[str], bool] = _pacman_has,
) -> list[dict]:
    status = []
    for item in manifest["items"]:
        missing = _missing(item, repo, is_pkg_installed)
        status.append(
            {
                "id": item["id"],
                "title": item.get("title", item["id"]),
                "desc": item.get("desc", ""),
                "kind": item["kind"],
                "state": "missing" if missing else "ok",
                "missing": missing,
                "declined": item["id"] in declined,
                "terminal": bool(item.get("terminal")),
                "requires": item.get("requires", []),
            }
        )
    return status


def pending(status: list[dict]) -> list[dict]:
    return [s for s in status if s["state"] == "missing" and not s["declined"]]


# ----------------------------------------------------------------------------- declined


def load_declined(state: Path) -> set[str]:
    try:
        data = json.loads((state / "declined.json").read_text(encoding="utf-8"))
        return {str(x) for x in data}
    except (OSError, ValueError, TypeError):
        return set()


def save_declined(state: Path, ids: set[str]) -> None:
    state.mkdir(parents=True, exist_ok=True)
    tmp = state / "declined.json.tmp"
    tmp.write_text(json.dumps(sorted(ids)), encoding="utf-8")
    tmp.replace(state / "declined.json")


# ----------------------------------------------------------------------------- install


def install_files(item: dict, repo: Path) -> list[str]:
    """Yalnızca yerelde olmayan dosyaları kopyalar; var olanlara dokunmaz."""
    executable = set(item.get("executable", []))
    copied = []
    for rel, src, dest in _file_pairs(item, repo):
        if os.path.lexists(dest):
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        if rel in executable:
            dest.chmod(0o755)
        copied.append(rel)
    return copied


def build_terminal_script(items: list[dict], repo: Path) -> str:
    lines = ["#!/bin/bash", "fail=0"]
    for item in items:
        cmd = item["install"].replace("{repo}", shlex.quote(str(repo)))
        lines += [
            f"# {item['id']}",
            f"echo; echo '== {item.get('title', item['id'])}'",
            f"{cmd} || {{ echo 'HATA: {item['id']}'; fail=1; }}",
        ]
    lines += ["echo", "read -rp 'Kapatmak için Enter...' _", "exit $fail"]
    return "\n".join(lines) + "\n"


def find_terminal(title: str, script: Path) -> list[str] | None:
    forced = os.environ.get("DOTSYNC_TERMINAL")
    candidates = {
        "kitty": ["kitty", "--title", title, "bash", str(script)],
        "foot": ["foot", "-T", title, "bash", str(script)],
        "alacritty": ["alacritty", "-T", title, "-e", "bash", str(script)],
        "xterm": ["xterm", "-T", title, "-e", "bash", str(script)],
    }
    for name in ([forced] if forced else []) + list(candidates):
        if name in candidates and shutil.which(name):
            return candidates[name]
    return None


# ----------------------------------------------------------------------------- sync


def _git(*args: str, cwd: Path | None = None, timeout: int = SYNC_TIMEOUT_S) -> bool:
    helper = ["-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential"]
    try:
        return subprocess.run(
            ["git", *helper, *args], cwd=cwd, capture_output=True, timeout=timeout, check=False
        ).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def sync(repo: Path, name: str) -> bool:
    """Önbelleği günceller. Çevrimdışıysa False döner; var olan önbellek kullanılmaya devam eder."""
    if not (repo / ".git").is_dir():
        repo.parent.mkdir(parents=True, exist_ok=True)
        try:
            return subprocess.run(
                ["gh", "repo", "clone", name, str(repo), "--", "--depth", "1"],
                capture_output=True,
                timeout=CLONE_TIMEOUT_S,
                check=False,
            ).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False
    return _git("fetch", "--depth", "1", "origin", cwd=repo) and _git(
        "reset", "--hard", "FETCH_HEAD", cwd=repo
    )


# ----------------------------------------------------------------------------- commands


def _emit(**event) -> None:
    print(json.dumps(event, ensure_ascii=False), flush=True)


def _load(do_sync: bool) -> tuple[dict, Path]:
    repo = repo_dir()
    if do_sync:
        sync(repo, repo_name())
    if not (repo / "manifest.json").exists():
        raise ManifestError(f"repo önbelleği yok ({repo}); internet/gh girişini kontrol edin")
    return load_manifest(repo), repo


def cmd_status(args: argparse.Namespace) -> int:
    manifest, repo = _load(args.sync)
    declined = set() if args.include_declined else load_declined(state_dir())
    status = compute_status(manifest, repo, declined)
    print(json.dumps({"items": status, "pending": [s["id"] for s in pending(status)]}, ensure_ascii=False))
    return 0


def _run_install(item: dict, repo: Path) -> bool:
    """Terminal gerektirmeyen öğelerin `install` komutu (varsa)."""
    cmd = item.get("install")
    if not cmd:
        return True
    cmd = cmd.replace("{repo}", shlex.quote(str(repo)))
    return subprocess.run(["bash", "-c", cmd], check=False).returncode == 0


def _run_post(item: dict) -> bool:
    ok = True
    for cmd in item.get("post", []):
        ok = subprocess.run(["bash", "-c", cmd], check=False).returncode == 0 and ok
    return ok


def cmd_apply(args: argparse.Namespace) -> int:
    manifest, repo = _load(False)
    by_id = {i["id"]: i for i in manifest["items"]}
    unknown = [i for i in args.ids + args.decline if i not in by_id]
    if unknown:
        _emit(event="error", detail=f"bilinmeyen öğe: {', '.join(unknown)}")
        return 2

    state = state_dir()
    save_declined(state, (load_declined(state) | set(args.decline)) - set(args.ids))

    wanted = [i for i in manifest["items"] if i["id"] in set(args.ids)]
    healthy = {s["id"] for s in compute_status(manifest, repo, set()) if s["state"] == "ok"}
    done: dict[str, bool] = {}
    terminal_batch: list[dict] = []

    for item in wanted:
        iid = item["id"]
        blockers = [r for r in item.get("requires", []) if r not in healthy and r not in args.ids]
        if blockers:
            _emit(event="done", id=iid, ok=False, detail=f"önkoşul eksik: {', '.join(blockers)}")
            done[iid] = False
            continue
        if item.get("terminal"):
            terminal_batch.append(item)
            continue
        _emit(event="start", id=iid)
        try:
            copied = install_files(item, repo) if item["kind"] == "files" else []
            ran = _run_install(item, repo) and _run_post(item)
            # Çıkış koduna değil gerçek duruma güven: öğe artık eksiksiz mi?
            now = {s["id"]: s for s in compute_status(manifest, repo, set())}[iid]
            ok = ran and now["state"] == "ok"
            detail = f"{len(copied)} dosya kopyalandı" if item["kind"] == "files" else ""
            if not ok and now["missing"]:
                detail = "eksik kaldı: " + ", ".join(now["missing"][:3])
        except OSError as exc:
            ok, detail = False, str(exc)
        done[iid] = ok
        _emit(event="done", id=iid, ok=ok, detail=detail)

    if terminal_batch:
        for item in terminal_batch:
            _emit(event="start", id=item["id"])
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as fh:
            fh.write(build_terminal_script(terminal_batch, repo))
            script = Path(fh.name)
        cmd = find_terminal("dotsync", script)
        if cmd is None:
            for item in terminal_batch:
                _emit(event="done", id=item["id"], ok=False, detail="terminal bulunamadı (kitty/foot/alacritty/xterm)")
        else:
            subprocess.run(cmd, check=False)
            after = {s["id"]: s for s in compute_status(manifest, repo, set())}
            for item in terminal_batch:
                ok = after[item["id"]]["state"] == "ok"
                done[item["id"]] = ok
                _emit(event="done", id=item["id"], ok=ok, detail="" if ok else "terminalde tamamlanmadı")
        script.unlink(missing_ok=True)

    _emit(event="finished", ok=all(done.values()) if done else True)
    return 0 if all(done.values()) else 1


def cmd_decline(args: argparse.Namespace) -> int:
    state = state_dir()
    save_declined(state, load_declined(state) | set(args.ids))
    return 0


def cmd_reset(_args: argparse.Namespace) -> int:
    save_declined(state_dir(), set())
    return 0


def cmd_sync(_args: argparse.Namespace) -> int:
    return 0 if sync(repo_dir(), repo_name()) else 1


def _launch_ui(mode: str | None) -> int:
    ui = Path(__file__).resolve().parent / "ui"
    env = {**os.environ, "DOTSYNC_BIN": str(Path(__file__).resolve())}
    if mode:
        env["DOTSYNC_MODE"] = mode
    return subprocess.run(["qs", "-p", str(ui)], env=env, check=False).returncode


def cmd_boot(_args: argparse.Namespace) -> int:
    """Açılış denetimi: sessiz; yalnızca bekleyen (ve reddedilmemiş) eksik varsa arayüz açar."""
    try:
        manifest, repo = _load(True)
    except ManifestError as exc:
        print(f"dotsync: {exc}", file=sys.stderr)
        return 0
    status = compute_status(manifest, repo, load_declined(state_dir()))
    if not pending(status) or os.environ.get("DOTSYNC_NO_UI"):
        return 0
    return _launch_ui(None)


def cmd_setup(_args: argparse.Namespace) -> int:
    """Kurulum ekranı: her zaman açılır, reddedilenleri de gösterir, eksik yoksa 'hepsi kurulu' der."""
    _load(True)  # önbelleği tazele; ManifestError main'de yakalanır
    if os.environ.get("DOTSYNC_NO_UI"):
        return 0
    return _launch_ui("setup")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="dotsync", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("status")
    p.add_argument("--sync", action="store_true")
    p.add_argument("--include-declined", action="store_true", help="reddedilenleri de bekleyen say")
    p.set_defaults(fn=cmd_status)

    p = sub.add_parser("apply")
    p.add_argument("ids", nargs="*", default=[])
    p.add_argument("--decline", nargs="*", default=[])
    p.set_defaults(fn=cmd_apply)

    p = sub.add_parser("decline")
    p.add_argument("ids", nargs="+")
    p.set_defaults(fn=cmd_decline)

    sub.add_parser("reset").set_defaults(fn=cmd_reset)
    sub.add_parser("sync").set_defaults(fn=cmd_sync)
    sub.add_parser("boot").set_defaults(fn=cmd_boot)
    sub.add_parser("setup").set_defaults(fn=cmd_setup)

    args = parser.parse_args(argv)
    try:
        return args.fn(args)
    except ManifestError as exc:
        print(f"dotsync: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
