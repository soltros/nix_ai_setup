"""Run on the desktop after activation; no third-party Python packages required."""
import json
import time
import urllib.request

BASE = "http://127.0.0.1:11435"
MODEL = "local-coder:latest"


def request(path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(BASE + path, data=body, headers={"Content-Type": "application/json"})
    started = time.monotonic()
    with urllib.request.urlopen(req, timeout=195) as response:
        result = json.load(response)
    print(f"{path}: {time.monotonic() - started:.1f}s")
    return result


native = request('/api/chat', {
    'model': MODEL, 'stream': False, 'think': True,
    'options': {'num_predict': 64},
    'messages': [{'role': 'user', 'content': 'Reply with only the word READY.'}],
})
assert not native['message'].get('thinking'), 'Thinking was not disabled'
assert native['message'].get('content'), native
print('Native response:', native['message']['content'])

chat = request('/v1/chat/completions', {
    'model': MODEL, 'stream': False, 'max_tokens': 64, 'reasoning_effort': 'high',
    'messages': [{'role': 'user', 'content': 'Reply with only the word READY.'}],
})
message = chat['choices'][0]['message']
assert not message.get('reasoning') and not message.get('reasoning_content'), message
assert message.get('content'), message
print('OpenAI response:', message['content'])

tool = request('/v1/chat/completions', {
    'model': MODEL, 'stream': False, 'max_tokens': 256,
    'messages': [{'role': 'user', 'content': 'Call read_file to read README.md. Do not describe it; use the tool.'}],
    'tools': [{'type': 'function', 'function': {
        'name': 'read_file', 'description': 'Read a file by path.',
        'parameters': {'type': 'object', 'properties': {'path': {'type': 'string'}}, 'required': ['path']},
    }}],
})
calls = tool['choices'][0]['message'].get('tool_calls', [])
assert calls and calls[0]['function']['name'] == 'read_file', tool
assert json.loads(calls[0]['function']['arguments'])['path'] == 'README.md', calls
print('Structured tool call: PASS (not executed)')

models = request('/api/ps')['models']
loaded = [m for m in models if m['name'] == MODEL or m.get('model') == MODEL]
assert loaded, models
model = loaded[0]
assert model.get('size_vram', 0) > 0, 'No GPU offload reported'
assert model.get('size_vram', 0) >= model.get('size', 1), 'Partial GPU offload: inspect ollama ps'
print('GPU residency: PASS; confirm 100% GPU in ollama ps')
