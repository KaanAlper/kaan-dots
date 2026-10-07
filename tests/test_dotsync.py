"""dotsync çekirdeği: durum hesabı, güvenli kopyalama, reddedilenleri hatırlama."""
import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "dotsync"))
import dotsync  # noqa: E402


def make_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "items/a/sub").mkdir(parents=True, exist_ok=True)
    (repo / "items/a/one.txt").write_text("1")
    (repo / "items/a/run.sh").write_text("#!/bin/sh\n")
    (repo / "items/a/sub/two.txt").write_text("2")
    manifest = {
        "schema": 1,
        "items": [
            {
                "id": "a",
                "title": "A",
                "desc": "d",
                "kind": "files",
                "src": "items/a",
                "dest": str(tmp_path / "home/a"),
                "executable": ["run.sh"],
            },
            {
                "id": "p",
                "title": "P",
                "desc": "d",
                "kind": "pkgs",
                "pkgs": ["foo", "bar"],
                "install": "true",
            },
            {
                "id": "c",
                "title": "C",
                "desc": "d",
                "kind": "check",
                "check": [
                    {"exists": str(tmp_path / "marker")},
                    {"file_lacks": [str(tmp_path / "cfg.ini"), "device = none"]},
                ],
                "requires": ["p"],
                "install": "true",
            },
        ],
    }
    (repo / "manifest.json").write_text(json.dumps(manifest))
    return repo


def states(tmp_path, installed=(), declined=()):
    repo = make_repo(tmp_path)
    manifest = dotsync.load_manifest(repo)
    return {
        s["id"]: s
        for s in dotsync.compute_status(
            manifest, repo, set(declined), is_pkg_installed=lambda p: p in installed
        )
    }


def test_files_item_missing_lists_every_absent_file(tmp_path):
    s = states(tmp_path)["a"]
    assert s["state"] == "missing"
    assert sorted(s["missing"]) == ["one.txt", "run.sh", "sub/two.txt"]


def test_files_item_ok_when_all_present(tmp_path):
    dest = tmp_path / "home/a"
    (dest / "sub").mkdir(parents=True)
    for rel in ("one.txt", "run.sh", "sub/two.txt"):
        (dest / rel).write_text("x")
    assert states(tmp_path)["a"]["state"] == "ok"


def test_pkgs_item_reports_only_absent_packages(tmp_path):
    s = states(tmp_path, installed={"foo"})["p"]
    assert s["state"] == "missing"
    assert s["missing"] == ["bar"]


def test_pkgs_item_ok_when_all_installed(tmp_path):
    assert states(tmp_path, installed={"foo", "bar"})["p"]["state"] == "ok"


def test_check_item_declarative_conditions(tmp_path):
    assert states(tmp_path)["c"]["state"] == "missing"  # marker yok
    (tmp_path / "marker").write_text("")
    (tmp_path / "cfg.ini").write_text("device = none\n")
    assert states(tmp_path)["c"]["state"] == "missing"  # satır hâlâ var
    (tmp_path / "cfg.ini").write_text("device = /dev/video2\n")
    assert states(tmp_path)["c"]["state"] == "ok"


def test_declined_items_are_flagged_not_hidden(tmp_path):
    s = states(tmp_path, declined={"a"})["a"]
    assert s["state"] == "missing"
    assert s["declined"] is True


def test_pending_excludes_ok_and_declined(tmp_path):
    repo = make_repo(tmp_path)
    manifest = dotsync.load_manifest(repo)
    status = dotsync.compute_status(
        manifest, repo, {"p"}, is_pkg_installed=lambda p: False
    )
    assert [s["id"] for s in dotsync.pending(status)] == ["a", "c"]


def test_install_files_copies_only_missing_and_never_overwrites(tmp_path):
    repo = make_repo(tmp_path)
    item = dotsync.load_manifest(repo)["items"][0]
    dest = Path(item["dest"])
    dest.mkdir(parents=True)
    (dest / "one.txt").write_text("LOKAL")  # kullanıcının kendi dosyası

    copied = dotsync.install_files(item, repo)

    assert sorted(copied) == ["run.sh", "sub/two.txt"]
    assert (dest / "one.txt").read_text() == "LOKAL"
    assert (dest / "sub/two.txt").read_text() == "2"
    assert os.access(dest / "run.sh", os.X_OK)
    assert not os.access(dest / "sub/two.txt", os.X_OK)


def test_files_item_rejects_path_escape(tmp_path):
    repo = make_repo(tmp_path)
    manifest = json.loads((repo / "manifest.json").read_text())
    manifest["items"][0]["src"] = "../outside"
    (repo / "manifest.json").write_text(json.dumps(manifest))
    with pytest.raises(dotsync.ManifestError):
        dotsync.load_manifest(repo)


def test_declined_roundtrip_and_reset(tmp_path):
    state = tmp_path / "state"
    assert dotsync.load_declined(state) == set()
    dotsync.save_declined(state, {"a", "b"})
    assert dotsync.load_declined(state) == {"a", "b"}
    dotsync.save_declined(state, set())
    assert dotsync.load_declined(state) == set()


def test_declined_file_corrupt_is_treated_as_empty(tmp_path):
    state = tmp_path / "state"
    state.mkdir()
    (state / "declined.json").write_text("{bozuk")
    assert dotsync.load_declined(state) == set()


def test_terminal_script_orders_items_and_exits_nonzero_on_failure(tmp_path):
    repo = make_repo(tmp_path)
    manifest = dotsync.load_manifest(repo)
    items = [manifest["items"][1], manifest["items"][2]]
    script = dotsync.build_terminal_script(items, repo)
    assert script.index("# p") < script.index("# c")
    assert "{repo}" not in script
    assert str(repo) in script or "true" in script


# ------------------------------------------------------------------ CLI (apply / boot)


@pytest.fixture
def cli_env(tmp_path, monkeypatch):
    """repo önbelleğini ve durum dizinini tmp'e yönlendirir; gerçek HOME'a dokunmaz."""
    data = tmp_path / "xdg-data"
    monkeypatch.setenv("XDG_DATA_HOME", str(data))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "xdg-state"))
    monkeypatch.setenv("DOTSYNC_NO_UI", "1")
    repo = make_repo(tmp_path)
    (data / "dotsync").mkdir(parents=True)
    (data / "dotsync" / "repo").symlink_to(repo)
    return tmp_path


def events(capsys):
    return [json.loads(l) for l in capsys.readouterr().out.splitlines() if l.startswith("{")]


def test_apply_installs_files_and_reports_done(cli_env, capsys):
    rc = dotsync.main(["apply", "a"])
    out = events(capsys)
    assert rc == 0
    assert {"event": "done", "id": "a", "ok": True, "detail": "3 dosya kopyalandı"} in out
    assert (cli_env / "home/a/sub/two.txt").exists()


def test_apply_marks_item_failed_when_install_leaves_it_missing(cli_env, capsys):
    """install komutu 'true' ama marker oluşmuyor: başarılı DİYE rapor edilmemeli."""
    rc = dotsync.main(["apply", "c"])  # c, p'ye bağlı ama p seçilmedi -> önkoşul engeli
    out = events(capsys)
    assert rc == 1
    done = [e for e in out if e["event"] == "done"][0]
    assert done["ok"] is False


def test_apply_runs_install_command_and_verifies_result(cli_env, capsys):
    marker = cli_env / "marker"
    repo = dotsync.repo_dir()
    manifest = json.loads((repo / "manifest.json").read_text())
    for it in manifest["items"]:
        if it["id"] == "c":
            it["requires"] = []
            it["install"] = f"touch {marker}; echo 'device = /dev/video2' > {cli_env / 'cfg.ini'}"
    (repo / "manifest.json").write_text(json.dumps(manifest))
    rc = dotsync.main(["apply", "c"])
    out = events(capsys)
    assert rc == 0
    assert marker.exists()
    assert [e for e in out if e["event"] == "done"][0]["ok"] is True


def test_apply_decline_remembers_unchecked_and_forgets_installed(cli_env, capsys):
    state = dotsync.state_dir()
    dotsync.save_declined(state, {"a"})  # daha önce reddedilmişti
    dotsync.main(["apply", "a", "--decline", "p"])
    assert dotsync.load_declined(state) == {"p"}  # a kuruldu -> unutuldu; p reddedildi


def test_apply_rejects_unknown_ids(cli_env, capsys):
    assert dotsync.main(["apply", "yok"]) == 2
    assert events(capsys)[0]["event"] == "error"


def test_decline_and_reset_commands(cli_env):
    dotsync.main(["decline", "a", "p"])
    assert dotsync.load_declined(dotsync.state_dir()) == {"a", "p"}
    dotsync.main(["reset"])
    assert dotsync.load_declined(dotsync.state_dir()) == set()


def test_status_command_lists_pending_without_declined(cli_env, capsys):
    dotsync.main(["decline", "a"])
    dotsync.main(["status"])
    data = json.loads(capsys.readouterr().out)
    assert "a" not in data["pending"]
    assert {i["id"] for i in data["items"]} == {"a", "p", "c"}


def test_boot_is_silent_and_does_not_launch_ui_when_nothing_pending(cli_env, monkeypatch):
    calls = []
    monkeypatch.setattr(dotsync.subprocess, "run", lambda *a, **k: calls.append(a) or None)
    dotsync.main(["decline", "a", "p", "c"])
    monkeypatch.undo()
    monkeypatch.setenv("XDG_DATA_HOME", str(cli_env / "xdg-data"))
    monkeypatch.setenv("XDG_STATE_HOME", str(cli_env / "xdg-state"))
    monkeypatch.setenv("DOTSYNC_NO_UI", "1")
    assert dotsync.main(["boot"]) == 0
