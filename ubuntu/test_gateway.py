import asyncio
import unittest
from unittest.mock import patch

from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

import gateway
from gateway import TOKENS, constrain


class Limits(unittest.TestCase):
    def test_native_caps_generation_and_disables_thinking(self):
        result = constrain(
            "/api/chat",
            {"think": True, "options": {"num_predict": -1, "num_ctx": 999999}},
        )
        self.assertFalse(result["think"])
        self.assertEqual(result["options"]["num_predict"], TOKENS)
        # Context belongs to each tuned model alias and is not rewritten here.
        self.assertEqual(result["options"]["num_ctx"], 999999)

    def test_openai_caps_both_output_fields(self):
        result = constrain(
            "/v1/chat/completions",
            {
                "max_tokens": 99999,
                "max_completion_tokens": 128,
                "reasoning": {"effort": "high"},
                "n": 10,
            },
        )
        self.assertEqual(result["max_tokens"], 128)
        self.assertNotIn("max_completion_tokens", result)
        self.assertEqual(result["reasoning_effort"], "none")
        self.assertEqual(result["reasoning"], {"effort": "none"})
        self.assertEqual(result["n"], 1)

    def test_smaller_limit_and_tools_preserved(self):
        tools = [{"type": "function", "function": {"name": "read_file"}}]
        result = constrain(
            "/v1/chat/completions",
            {"max_tokens": 32, "tools": tools},
        )
        self.assertEqual(result["max_tokens"], 32)
        self.assertEqual(result["tools"], tools)

    def test_invalid_limits_cannot_disable_cap(self):
        for value in [None, -1, 0, True, "unlimited", 1.5]:
            result = constrain("/api/chat", {"options": {"num_predict": value}})
            self.assertEqual(result["options"]["num_predict"], TOKENS)

    def test_invalid_payload_rejected(self):
        for payload in [[], None, {"options": []}]:
            with self.assertRaises(ValueError):
                constrain("/api/chat", payload)


class HTTPBehavior(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.received = None

        async def backend(request):
            self.received = await request.json()
            if self.received.get("slow"):
                await asyncio.sleep(1)
            if self.received.get("stream"):
                response = web.StreamResponse(
                    headers={"Content-Type": "text/event-stream"}
                )
                await response.prepare(request)
                await response.write(b'data: {"choices":[]}\n\n')
                await response.write(b"data: [DONE]\n\n")
                await response.write_eof()
                return response
            return web.json_response({"received": self.received})

        app = web.Application()
        app.router.add_post("/v1/chat/completions", backend)
        self.backend = TestServer(app)
        await self.backend.start_server()
        self.patch = patch.object(
            gateway, "BACKEND", str(self.backend.make_url("")).rstrip("/")
        )
        self.patch.start()
        self.client = TestClient(TestServer(gateway.make_app()))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()
        await self.backend.close()
        self.patch.stop()

    async def test_stream_passes_through_and_is_constrained(self):
        response = await self.client.post(
            "/v1/chat/completions",
            json={"stream": True, "reasoning_effort": "high"},
        )
        self.assertEqual(response.status, 200)
        self.assertIn("data: [DONE]", await response.text())
        self.assertEqual(self.received["reasoning_effort"], "none")
        self.assertEqual(self.received["max_tokens"], TOKENS)

    async def test_deadline_returns_gateway_timeout(self):
        with patch.object(gateway, "DEADLINE", 0.02):
            response = await self.client.post(
                "/v1/chat/completions", json={"slow": True}
            )
            self.assertEqual(response.status, 504)

    async def test_management_is_not_forwarded(self):
        response = await self.client.post("/api/delete", json={"model": "x"})
        self.assertEqual(response.status, 404)
        self.assertIsNone(self.received)


if __name__ == "__main__":
    unittest.main()
