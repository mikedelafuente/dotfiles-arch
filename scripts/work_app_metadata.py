"""Read-only APT source and Zoom signed-manifest validation."""
import hashlib
from pathlib import Path
import re
import sys

APT_URLS = {
    "chrome": {"https://dl.google.com/linux/chrome/deb", "https://dl.google.com/linux/chrome-stable/deb"},
    "slack": {"https://packagecloud.io/slacktechnologies/slack/debian"},
    "tableplus": {"https://deb.tableplus.com/debian/26"},
    "spotify": {"https://repository.spotify.com"},
}
APT_VENDORS = {
    "chrome": r"dl(-ssl)?\.google\.com/linux/chrome",
    "slack": r"packagecloud\.io/slacktechnologies/slack|packages\.slack-edge\.com",
    "tableplus": r"(?:deb|apt)\.tableplus\.com",
    "spotify": r"(?:repository|download)\.spotify\.com",
}


def apt_key(app, text):
    urls, vendor = APT_URLS[app], APT_VENDORS[app]
    component = "non-free" if app == "spotify" else "main"
    if re.search(r"^\s*(?:#\s*)?deb(?:-src)?\s", text, re.M):
        records = [line for line in text.splitlines() if re.search(vendor, line)
                   and re.match(r"\s*(?:#\s*)?deb(?:-src)?\s", line)]
    else:
        records = [block for block in re.split(r"\n\s*\n", text.strip()) if re.search(vendor, block)]
    if len(records) != 1:
        raise ValueError("missing or duplicate vendor source")
    text = records[0]
    lines = [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if len(lines) == 1 and lines[0].startswith("deb "):
        match = re.fullmatch(r"deb\s+\[([^]]+)\]\s+(\S+)\s+(\S+)\s+" + component, lines[0])
        if not match:
            raise ValueError("unscoped or malformed source")
        options = dict(item.split("=", 1) for item in match[1].split())
        if set(options) - {"arch", "signed-by"} or options.get("arch", "amd64") != "amd64":
            raise ValueError("unsupported source options")
        url, suite, key = match[2], match[3], options.get("signed-by", "")
    else:
        fields = {}
        for line in lines:
            name, value = line.split(":", 1)
            if name in fields:
                raise ValueError("multiple sources or duplicate fields")
            fields[name] = value.strip()
        if set(fields) - {"Types", "URIs", "Suites", "Components", "Architectures", "Signed-By", "X-Repolib-Name"}:
            raise ValueError("unsupported source fields")
        if fields.get("Types") != "deb" or fields.get("Components") != component or fields.get("Architectures", "amd64") != "amd64":
            raise ValueError("unsupported source layout")
        url, suite, key = fields.get("URIs", ""), fields.get("Suites", ""), fields.get("Signed-By", "")
    suites = {"slack": "jessie", "tableplus": "tableplus"}
    if url.rstrip("/") not in urls or suite != suites.get(app, "stable"):
        raise ValueError("unexpected vendor source")
    if not re.fullmatch(r"/(?:etc/apt/keyrings|usr/share/keyrings)/[A-Za-z0-9_.-]+\.(?:gpg|asc)", key):
        raise ValueError("repository-scoped signing key required")
    return key


def package_version(app, version):
    pattern = r"[0-9]+(?:\.[0-9]+)+(?:\.g[a-f0-9]+)?(?:[-+][A-Za-z0-9.]+)?" if app == "spotify" else r"[0-9]+(?:\.[0-9]+)+(?:[-+][A-Za-z0-9.]+)?"
    if app not in {"chrome", "slack", "zoom", "tableplus", "spotify", "obsidian"} or not re.fullmatch(pattern, version):
        raise ValueError("missing stable package version")
    minimum = {"slack": (4, 35, 121), "zoom": (6, 7, 5)}.get(app, (0,))
    numbers = tuple(map(int, re.split(r"[-+]|\.g", version)[0].split(".")))
    if numbers < minimum:
        raise ValueError(f"{app} package version is incompatible; update through selected owner")
    return version


def apt_candidate(app, text):
    candidate = re.search(r"^  Candidate: (\S+)$", text, re.M)
    if not candidate:
        raise ValueError("missing stable APT candidate")
    version = candidate[1]
    package_version(app, version)
    urls = APT_URLS[app]
    selected, origins = False, []
    for line in text.splitlines():
        header = re.fullmatch(r"\s+(?:\*\*\* )?(\S+) +[0-9]+", line)
        if header:
            selected = header[1] == version
        elif selected:
            origin = re.fullmatch(r"\s+[0-9]+ +(\S+) +(\S+) +amd64 Packages", line)
            if origin:
                origins.append(origin[1].rstrip("/"))
            elif "Packages" in line:
                raise ValueError("unknown candidate origin")
    if not origins or any(origin not in urls for origin in origins):
        raise ValueError("candidate has unknown/conflicting update owner")
    return version


def zoom_members(path):
    """Read standard ar members without extracting paths or executing package contents."""
    members = {}
    with Path(path).open("rb") as archive:
        if archive.read(8) != b"!<arch>\n":
            raise ValueError("not a Debian archive")
        while header := archive.read(60):
            if len(header) != 60 or header[58:] != b"`\n":
                raise ValueError("invalid ar header")
            name = header[:16].decode("ascii").strip().rstrip("/")
            size = int(header[48:58])
            if size < 0 or name in members or not re.fullmatch(r"(?:debian-binary|(?:control|data)\.tar(?:\.(?:gz|xz|zst|bz2|lzma))?|_gpgbuilder)", name):
                raise ValueError("unexpected or duplicate archive member")
            md5, sha1 = hashlib.md5(), hashlib.sha1()
            remaining = size
            while remaining:
                chunk = archive.read(min(remaining, 1024 * 1024))
                if not chunk:
                    raise ValueError("truncated archive")
                md5.update(chunk)
                sha1.update(chunk)
                remaining -= len(chunk)
            if size % 2 and archive.read(1) != b"\n":
                raise ValueError("invalid ar padding")
            members[name] = (md5.hexdigest(), sha1.hexdigest(), size)
    if "_gpgbuilder" not in members or "debian-binary" not in members or len(members) != 4:
        raise ValueError("expected signed Zoom Debian archive")
    if sum(name.startswith("control.tar") for name in members) != 1 or sum(name.startswith("data.tar") for name in members) != 1:
        raise ValueError("missing Debian control/data archive")
    return {name: value for name, value in members.items() if name != "_gpgbuilder"}


def zoom_manifest(path, text):
    """Compare GPG-authenticated dpkg-sig v4 manifest with every package member."""
    if not re.search(r"^Version: 4$", text, re.M) or not re.search(r"^Role: builder$", text, re.M):
        raise ValueError("unsupported Zoom signature manifest")
    rows = {}
    in_files = False
    for line in text.splitlines():
        if line == "Files:":
            if in_files:
                raise ValueError("duplicate Files field")
            in_files = True
        elif in_files:
            match = re.fullmatch(r" ([a-f0-9]{32}) ([a-f0-9]{40}) ([0-9]+) (\S+)", line)
            if not match or match[4] in rows:
                raise ValueError("invalid signed file list")
            rows[match[4]] = (match[1], match[2], int(match[3]))
    if rows != zoom_members(path):
        raise ValueError("Zoom package differs from signed manifest")


if __name__ == "__main__":
    try:
        if sys.argv[1] == "apt-key":
            print(apt_key(sys.argv[2], sys.argv[3]))
        elif sys.argv[1] == "package-version":
            print(package_version(sys.argv[2], sys.argv[3]))
        elif sys.argv[1] == "apt-candidate":
            print(apt_candidate(sys.argv[2], sys.argv[3]))
        elif sys.argv[1] == "zoom-manifest":
            zoom_manifest(sys.argv[2], Path(sys.argv[3]).read_text())
        else:
            raise ValueError("unknown decision")
    except (ValueError, KeyError, IndexError, OSError, UnicodeError) as error:
        print(f"Work app source/verification conflict: {error}; preserved", file=sys.stderr)
        sys.exit(1)
