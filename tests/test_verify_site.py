"""Exercise the public verifier CLI against the real Astro build over HTTP."""

import subprocess
import sys
import threading
import unittest
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "site/dist"


class SiteVerifierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (DIST / "index.html").is_file() or not (DIST / "404.html").is_file():
            raise RuntimeError(
                "Build the site first: npm --prefix site ci && npm --prefix site run build"
            )

    def verify_build(self, scenario):
        class Handler(SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=str(DIST), **kwargs)

            def log_message(self, *_):
                pass

            def do_GET(self):
                route = urlsplit(self.path).path.rstrip("/")
                if scenario == "empty" or route == "/404":
                    self.send_error(404)
                    return
                if scenario == "install_home" and route == "/install":
                    self.path = "/"
                super().do_GET()

            def send_error(self, code, message=None, explain=None):
                if code != 404:
                    return super().send_error(code, message, explain)
                # Match static hosting's custom 404, or an empty deployment.
                body = b"404: NOT_FOUND" if scenario == "empty" else (DIST / "404.html").read_bytes()
                self.send_response(404)
                self.send_header("Content-Type", "text/plain" if scenario == "empty" else "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        with HTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(
                target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True
            )
            thread.start()
            try:
                return subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "scripts/verify_site.py"),
                        "--origin",
                        f"http://127.0.0.1:{server.server_port}",
                    ],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
            finally:
                server.shutdown()
                thread.join(timeout=5)

    def assert_rejected(self, result):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"\d+ passed, [1-9]\d* failed, \d+ checks")

    def test_real_site_build_is_accepted(self):
        result = self.verify_build("valid")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_empty_deployment_is_rejected(self):
        self.assert_rejected(self.verify_build("empty"))

    def test_homepage_at_install_route_is_rejected(self):
        result = self.verify_build("install_home")
        self.assert_rejected(result)


if __name__ == "__main__":
    unittest.main()
