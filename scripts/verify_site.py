#!/usr/bin/env python3
"""Check the deployed Houdini site without credentials or provider requests."""

import argparse
import re
import sys
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from xml.etree import ElementTree

ROUTES = ("/", "/install", "/guide", "/reveals", "/surfaces", "/privacy", "/faq")
REPOSITORY = "https://github.com/vitorsalomao05/houdini"
INSTALLER = "https://raw.githubusercontent.com/vitorsalomao05/houdini/"
CANONICAL_ORIGIN = "https://houdini.salomao.org"


class Page(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.text = []
        self.links = []
        self.canonicals = []
        self.ids = set()
        self.assets = set()
        self.images = set()
        self.hidden = 0
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        if tag in ("script", "style"):
            self.hidden += 1
        if tag == "a" and attrs.get("href"):
            self.links.append(attrs["href"])
        if tag == "script" and attrs.get("src"):
            self.assets.add(attrs["src"])
        if tag == "link" and "canonical" in attrs.get("rel", "").split():
            self.canonicals.append(attrs.get("href", ""))
        if tag == "link" and set(attrs.get("rel", "").split()) & {"stylesheet", "icon", "modulepreload"}:
            if attrs.get("href"):
                self.assets.add(attrs["href"])
        if tag in ("img", "source"):
            images = set()
            if attrs.get("src"):
                images.add(attrs["src"])
            for candidate in attrs.get("srcset", "").split(","):
                if candidate.strip():
                    images.add(candidate.split()[0])
            self.images.update(images)
            self.assets.update(images)

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.hidden = max(0, self.hidden - 1)

    def handle_data(self, data):
        if not self.hidden:
            self.text.append(data)


class SameOriginRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlsplit(req.full_url).netloc != urlsplit(newurl).netloc:
            raise URLError("cross-origin redirect refused")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origin", default=CANONICAL_ORIGIN, help="site origin to verify")
    args = parser.parse_args()
    origin = args.origin.rstrip("/")
    parsed_origin = urlsplit(origin)
    if (parsed_origin.scheme not in ("http", "https") or not parsed_origin.netloc
            or parsed_origin.username or parsed_origin.password
            or parsed_origin.path or parsed_origin.query or parsed_origin.fragment):
        parser.error("--origin must be an http(s) origin without credentials, path, query or fragment")
    config = Path(__file__).resolve().parents[1] / "site/src/config.ts"
    match = re.search(r'export const version = "(\d+\.\d+\.\d+)";', config.read_text())
    if not match:
        parser.error("cannot read expected version from site/src/config.ts")
    version = match.group(1)
    expected_tag = f"v{version}"
    expected_installer = f"{INSTALLER}{expected_tag}/install.sh"
    opener = build_opener(SameOriginRedirects())
    passed = failed = 0
    assets = set()

    def check(condition, label, detail=""):
        nonlocal passed, failed
        if condition:
            passed += 1
        else:
            failed += 1
        print(f"{'PASS' if condition else 'FAIL'} {label}" + (f" ({detail})" if detail else ""))

    def fetch(path):
        request = Request(urljoin(origin + "/", path), headers={"User-Agent": "Houdini-site-verifier/1"})
        try:
            with opener.open(request, timeout=15) as response:
                return response.status, response.read(), response.headers.get_content_type()
        except HTTPError as error:
            return error.code, error.read(), error.headers.get_content_type()
        except (URLError, TimeoutError, OSError) as error:
            print(f"ERROR {path}: {type(error).__name__}")
            return 0, b"", ""

    def local_path(reference, base="/"):
        url = urlsplit(urljoin(origin + base, reference))
        if (url.scheme, url.netloc) == (parsed_origin.scheme, parsed_origin.netloc):
            return url.path + (f"?{url.query}" if url.query else "")
        return None

    print(f"Verifying {origin}; expected Houdini {version}")
    for route in (*ROUTES, "/404", "/__houdini-production-check-not-found__"):
        status, body, content_type = fetch(route)
        expected_status = 200 if route in ROUTES else 404
        check(status == expected_status, f"{route} HTTP {expected_status}", f"observed {status}")
        html = body.decode("utf-8", errors="replace")
        page = Page(html)
        visible_text = " ".join(page.text)
        check("Houdini" in visible_text and content_type == "text/html", f"{route} branded HTML")
        canonical_route = route if route in ROUTES else "/404"
        expected_canonical = (CANONICAL_ORIGIN + canonical_route).rstrip("/")
        check(len(page.canonicals) == 1 and page.canonicals[0].rstrip("/") == expected_canonical,
              f"{route} canonical route")
        for reference in page.assets:
            path = local_path(reference, route)
            if path:
                assets.add(path)
        if route not in ROUTES:
            check("404" in visible_text and "Back to home" in visible_text, f"{route} branded not-found page")
            continue
        if route == "/install":
            check("install-wizard" in page.ids, f"{route} guided installer present")
        # Inspect visible product version text; Astro's generator metadata is unrelated.
        advertised = set(re.findall(r"\bv(\d+\.\d+\.\d+)\b", visible_text))
        check(advertised == {version}, f"{route} advertised version {version}", ", ".join(sorted(advertised)) or "none")
        installers = set(re.findall(re.escape(INSTALLER) + r'[^\s<>"\x27]+/install\.sh', unescape(html)))
        if route in ("/", "/install") or installers:
            check(installers == {expected_installer}, f"{route} pinned installer {expected_tag}")
        release_links = [link for link in page.links if link.startswith(REPOSITORY + "/releases")]
        check(bool(release_links), f"{route} release link present")
        if release_links:
            allowed = {REPOSITORY + "/releases", REPOSITORY + f"/releases/tag/{expected_tag}"}
            check(all(link.rstrip("/") in allowed for link in release_links), f"{route} release links current")
        if route in ("/", "/guide", "/surfaces"):
            name = "desktop-widget" if route == "/surfaces" else "popover-dark"
            check(any(name in image for image in page.images), f"{route} product screenshot present")

    check(any(path.endswith(".css") for path in assets), "local stylesheet referenced")
    check(any(path.endswith(".js") for path in assets), "local JavaScript referenced")
    for path in sorted(assets | {"/og.png"}):
        status, body, content_type = fetch(path)
        check(status == 200 and bool(body) and content_type != "text/html", f"asset {path}", f"HTTP {status}; {content_type}")

    status, body, _ = fetch("/robots.txt")
    robots = body.decode("utf-8", errors="replace")
    check(status == 200 and "User-agent:" in robots and "Sitemap:" in robots, "robots.txt", f"HTTP {status}")
    check(f"Sitemap: {CANONICAL_ORIGIN}/sitemap-index.xml" in robots, "robots sitemap pointer")
    sitemap_routes = set()
    pending = ["/sitemap-index.xml"]
    visited = set()
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        status, body, _ = fetch(path)
        try:
            root = ElementTree.fromstring(body)
            kind = root.tag.rsplit("}", 1)[-1]
            valid = status == 200 and kind in ("sitemapindex", "urlset")
        except ElementTree.ParseError:
            root, kind, valid = None, "", False
        check(valid, f"sitemap {path}", f"HTTP {status}")
        if not valid:
            continue
        for element in root.iter():
            if element.tag.rsplit("}", 1)[-1] != "loc" or not element.text:
                continue
            url = urlsplit(element.text.strip())
            if url.netloc != urlsplit(CANONICAL_ORIGIN).netloc:
                check(False, f"sitemap {path} canonical location")
                continue
            if kind == "sitemapindex":
                pending.append(url.path)
            else:
                sitemap_routes.add(url.path.rstrip("/") or "/")
    check(set(ROUTES) <= sitemap_routes, "sitemap contains all seven routes")
    print(f"\n{passed} passed, {failed} failed, {passed + failed} checks")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
