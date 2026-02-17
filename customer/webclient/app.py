"""OCP virt app migration agent WebClient — lightweight Python server with RM proxy."""

import logging
import os
import time

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("webclient")

app = FastAPI(title="WebClient")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
REQUEST_MANAGER_URL = os.environ.get(
    "REQUEST_MANAGER_URL",
    "http://self-service-agent-request-manager",
)

# Upstream can take 2+ min for multi-step LLM chains
# (routing → specialist → discovery → summarize)
UPSTREAM_TIMEOUT = 300.0

logger.info("WebClient starting — REQUEST_MANAGER_URL=%s  UPSTREAM_TIMEOUT=%s", REQUEST_MANAGER_URL, UPSTREAM_TIMEOUT)


# --------------- health ---------------
@app.get("/health")
async def health() -> JSONResponse:
    """Health check endpoint for OpenShift probes."""
    return JSONResponse({"status": "OK", "service": "webclient"})


# --------------- reverse proxy to Request Manager ---------------
@app.api_route("/api/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def proxy_to_request_manager(path: str, request: Request):
    """Forward any /api/* call to the in-cluster Request Manager."""
    target_url = f"{REQUEST_MANAGER_URL}/api/{path}"
    headers = {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in ("host", "content-length", "transfer-encoding")
    }
    body = await request.body()

    logger.info(
        "PROXY >>> %s %s  body_len=%d  headers=%s",
        request.method, target_url, len(body), dict(headers),
    )

    t0 = time.monotonic()

    try:
        async with httpx.AsyncClient(timeout=UPSTREAM_TIMEOUT) as client:
            resp = await client.request(
                method=request.method,
                url=target_url,
                headers=headers,
                content=body,
                params=request.query_params,
            )
    except httpx.TimeoutException as exc:
        elapsed = time.monotonic() - t0
        logger.error("PROXY TIMEOUT after %.1fs — %s %s — %s", elapsed, request.method, target_url, exc)
        return JSONResponse(
            content={"error": "The agent is still processing. Please try again in a moment."},
            status_code=504,
        )
    except httpx.ConnectError as exc:
        elapsed = time.monotonic() - t0
        logger.error("PROXY CONNECT ERROR after %.1fs — %s %s — %s", elapsed, request.method, target_url, exc)
        return JSONResponse(
            content={"error": f"Cannot reach Request Manager at {REQUEST_MANAGER_URL}: {exc}"},
            status_code=502,
        )
    except httpx.RequestError as exc:
        elapsed = time.monotonic() - t0
        logger.error("PROXY REQUEST ERROR after %.1fs — %s %s — %s", elapsed, request.method, target_url, exc)
        return JSONResponse(
            content={"error": f"Proxy error: {exc}"},
            status_code=502,
        )

    elapsed = time.monotonic() - t0
    logger.info(
        "PROXY <<< %s %s  status=%d  content_type=%s  body_len=%d  elapsed=%.1fs",
        request.method, target_url, resp.status_code,
        resp.headers.get("content-type", "?"), len(resp.content), elapsed,
    )

    # Log first 500 chars of upstream response for debugging
    resp_text = resp.text
    logger.info("PROXY <<< response_preview: %s", resp_text[:500])

    # Try to parse as JSON; fall back to raw text wrapper
    try:
        content = resp.json()
    except Exception:
        logger.warning("PROXY <<< response is NOT JSON — wrapping as {raw: ...}")
        content = {"raw": resp_text}

    return JSONResponse(content=content, status_code=resp.status_code)


# --------------- static files ---------------
@app.get("/")
async def root() -> FileResponse:
    """Serve the main page — no redirect, no trailing-slash issue."""
    return FileResponse(os.path.join(BASE_DIR, "index.html"))


@app.get("/index.html")
async def index_html() -> FileResponse:
    return FileResponse(os.path.join(BASE_DIR, "index.html"))


@app.get("/main.js")
async def main_js() -> FileResponse:
    return FileResponse(
        os.path.join(BASE_DIR, "main.js"),
        media_type="application/javascript",
    )


@app.get("/styles.css")
async def styles_css() -> FileResponse:
    return FileResponse(
        os.path.join(BASE_DIR, "styles.css"),
        media_type="text/css",
    )
