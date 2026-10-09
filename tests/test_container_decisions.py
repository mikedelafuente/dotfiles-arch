"""Supplied container/profile facts only; never execute setup or services."""
from pathlib import Path
import json
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="container-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt", "apt-get", "apt-cache",
                     "dpkg", "dpkg-query", "curl", "wget", "git", "docker",
                     "systemctl", "sysctl", "mkcert", "openvpn3", "openvpn3-admin",
                     "minikube", "kubectl", "k9s", "usermod"):
            script = guard / name
            script.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            script.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"),
                   USER_HOME_DIR=temp, PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected="", ok=True, diagnostic=""):
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + shlex.join(args)],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout
            assert diagnostic in result.stderr, result.stderr

        decide("docker_package_selection", "arch", "", "", expected="docker docker-compose docker-buildx")
        decide("docker_package_selection", "ubuntu", "docker.io", "/usr/bin/docker",
               expected="docker.io docker-compose-v2 docker-buildx")
        for packages, launcher in (("docker-ce docker-ce-cli containerd.io", "/usr/bin/docker"),
                                   ("docker.io docker-compose-plugin", "/usr/bin/docker"),
                                   ("podman-docker", "/usr/bin/docker"),
                                   ("docker.io", "/snap/bin/docker"),
                                   ("", "/usr/local/bin/docker")):
            decide("docker_package_selection", "ubuntu", packages, launcher,
                   ok=False, diagnostic="preserved")
        decide("docker_components_complete", "true", "true", "true")
        for engine, compose, buildx, missing in (("false", "true", "true", "Engine"),
                                                ("true", "false", "true", "Compose"),
                                                ("true", "true", "false", "Buildx")):
            decide("docker_components_complete", engine, compose, buildx,
                   ok=False, diagnostic=missing)
        decide("devcontainer_recipe", "ubuntu", "dig", expected="bind9-dnsutils dig native")
        decide("devcontainer_recipe", "ubuntu", "nss", expected="libnss3-tools certutil native")
        decide("devcontainer_recipe", "arch", "openvpn3", expected="openvpn3 openvpn3 aur")
        decide("devcontainer_recipe", "ubuntu", "openvpn3", expected="openvpn3-client openvpn3 native")
        decide("devcontainer_recipe", "fedora", "just", ok=False)
        decide("openvpn3_capabilities_complete", "true", "true")
        decide("openvpn3_capabilities_complete", "true", "false", ok=False, diagnostic="gap")
        for app in ("minikube", "kubectl", "k9s"):
            decide("editor_tool_selection", "ubuntu", app, "none", "", "", expected="upstream")
            decide("editor_tool_selection", "arch", app, "none", "", "1.39.0", expected="native")
            decide("editor_tool_selection", "ubuntu", app, "unknown", "1.39.0", "", ok=False)
        decide("editor_tool_version", "minikube", "v1.39.0", expected="1.39.0")
        decide("editor_tool_version", "kubectl", '{"clientVersion":{"gitVersion":"v1.35.0"}}', expected="1.35.0")
        for app, version, repo, asset in (("minikube", "1.39.0", "kubernetes/minikube", "minikube-linux-amd64"),
                                          ("k9s", "0.51.0", "derailed/k9s", "k9s_Linux_amd64.tar.gz")):
            url = f"https://github.com/{repo}/releases/download/v{version}/{asset}"
            metadata = {"tag_name": "v" + version, "prerelease": False, "draft": False,
                        "assets": [{"name": asset, "browser_download_url": url, "digest": "sha256:" + "a" * 64}]}
            decide("editor_release_asset", app, json.dumps(metadata), expected=version + " " + url + " " + "a" * 64)
            metadata["assets"][0]["digest"] = None
            decide("editor_release_asset", app, json.dumps(metadata), ok=False)
        decide("kubectl_release_asset", "v1.35.0", "b" * 64,
               expected="1.35.0 https://dl.k8s.io/release/v1.35.0/bin/linux/amd64/kubectl " + "b" * 64)
        decide("kubectl_release_asset", "v1.35.0-rc1", "b" * 64, ok=False)
        decide("kubectl_release_asset", "v1.35.0", "bad", ok=False)
        local_deb = "minikube:\n  Installed: 1.39.0\n  Candidate: 1.39.0\n  Version table:\n *** 1.39.0 100\n        100 /var/lib/dpkg/status"
        published = local_deb + "\n        500 https://example.com/ubuntu resolute/main amd64 Packages"
        decide("kubernetes_native_update_owner", "ubuntu", local_deb, ok=False, diagnostic="update owner")
        decide("kubernetes_native_update_owner", "ubuntu", published, expected="native")
        decide("kubernetes_native_update_owner", "arch", "", expected="native")
        decide("editor_tool_version", "k9s", "Version              v0.51.0\nCommit abc", expected="0.51.0")
        for app, output in (("k9s", "Version v0.51.0-rc1"), ("minikube", "v1.39.0-beta.1"),
                            ("kubectl", '{"clientVersion":{"gitVersion":"v1.35.0-alpha.1"}}')):
            decide("editor_tool_version", app, output, ok=False)
        decide("devcontainer_watch_limit", "1048576", expected="1048576")
        decide("devcontainer_watch_limit", "8192", expected="524288")
        decide("devcontainer_watch_limit", "unknown", ok=False)
        decide("devcontainer_dns_ready", "loaded", "true", "/run/systemd/resolve/stub-resolv.conf")
        decide("devcontainer_dns_ready", "not-found", "false", "", ok=False, diagnostic="DNS")
        decide("devcontainer_dns_ready", "loaded", "true", "/run/NetworkManager/resolv.conf",
               ok=False, diagnostic="DNS")
        for script in ("setup-docker.sh", "setup-minikube.sh", "setup-devcontainer.sh"):
            decide("require_workstation_entrypoint", "ubuntu", script)
        config = Path(temp) / ".docker/config.json"
        config.parent.mkdir()
        config.write_text('{"cliPluginsExtraDirs":[]}')
        decide("docker_plugins_allowed", str(config.parent))
        config.write_text('{"cliPluginsExtraDirs":["/custom"]}')
        decide("docker_plugins_allowed", str(config.parent), ok=False)
        config.write_text('{}')
        override = config.parent / "cli-plugins/docker-compose"
        override.parent.mkdir()
        override.symlink_to("/missing-custom-plugin")
        decide("docker_plugins_allowed", str(config.parent), ok=False)
    print("Container decisions passed (no setup/network/service workflows executed)")


if __name__ == "__main__":
    main()
