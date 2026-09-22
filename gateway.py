"""Loopback Ollama gateway: bounded generation for native and OpenAI clients."""
import asyncio
import json
import os
from aiohttp import ClientError, ClientSession, ClientTimeout, web

BACKEND = os.getenv("AI_BACKEND", "http://127.0.0.1:11434")
TOKENS = int(os.getenv("AI_MAX_TOKENS", "4096"))
CONTEXT = int(os.getenv("AI_CONTEXT", "16384"))
DEADLINE = int(os.getenv("AI_TIMEOUT", "180"))
GENERATE = {"/api/chat", "/api/generate", "/v1/chat/completions", "/v1/completions"}
READ = {"/", "/api/version", "/api/tags", "/api/ps", "/api/show", "/v1/models"}


def bounded(value, cap):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return cap
    return min(value, cap)


def constrain(path, data):
    if not isinstance(data, dict):
        raise ValueError("Expected a JSON object")
    if path.startswith("/api/"):
        data["think"] = False
        opts = data.setdefault("options", {})
        if not isinstance(opts, dict):
            raise ValueError("options must be an object")
        opts["num_predict"] = bounded(opts.get("num_predict"), TOKENS)
        opts["num_ctx"] = CONTEXT
        opts.setdefault("temperature", 0.7)
        opts.setdefault("top_p", 0.8)
        opts.setdefault("top_k", 20)
        opts.setdefault("presence_penalty", 1.5)
    else:
        data["max_tokens"] = min(bounded(data.get("max_tokens"), TOKENS),
                                 bounded(data.pop("max_completion_tokens", None), TOKENS))
        if path == "/v1/chat/completions":
            data["reasoning_effort"] = "none"
            data["reasoning"] = {"effort": "none"}
        data["n"] = 1
        data.setdefault("temperature", 0.7)
        data.setdefault("top_p", 0.8)
        data.setdefault("presence_penalty", 1.5)
    return data


async def proxy(request):
    path = request.path
    allowed = path in GENERATE or path in READ or path.startswith("/v1/models/")
    if not allowed or request.method not in {"GET", "HEAD", "POST"}:
        raise web.HTTPNotFound(text="Use the Ollama CLI on port 11434 for model management.")
    response = None
    try:
        body = await request.read()
        if path in GENERATE:
            body = json.dumps(constrain(path, json.loads(body))).encode()
        async with asyncio.timeout(DEADLINE):
            async with request.app["client"].request(
                request.method, BACKEND + request.rel_url.path_qs,
                data=body or None, headers={"Content-Type": "application/json"},
            ) as upstream:
                response = web.StreamResponse(status=upstream.status, headers={
                    "Content-Type": upstream.headers.get("Content-Type", "application/json")})
                await response.prepare(request)
                async for chunk in upstream.content.iter_any():
                    await response.write(chunk)
                await response.write_eof()
                return response
    except (ValueError, TypeError) as exc:
        raise web.HTTPBadRequest(text=str(exc)) from exc
    except (TimeoutError, OSError, ClientError) as exc:
        if response is not None and response.prepared:
            # Never report a truncated generation as a successful complete stream.
            if request.transport:
                request.transport.abort()
            return response
        raise web.HTTPGatewayTimeout(text="Local generation deadline reached or backend unavailable.") from exc


async def client_context(app):
    async with ClientSession(timeout=ClientTimeout(total=None)) as client:
        app["client"] = client
        yield


def make_app():
    app = web.Application(client_max_size=32 * 1024 * 1024)
    app.cleanup_ctx.append(client_context)
    app.router.add_route("*", "/{path:.*}", proxy)
    return app


if __name__ == "__main__":
    web.run_app(make_app(), host="127.0.0.1", port=int(os.getenv("AI_PORT", "11435")),
                handler_cancellation=True, access_log=None)
