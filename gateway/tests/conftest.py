"""Shared test fixtures."""

from __future__ import annotations

import os

import pytest

# Configure the gateway BEFORE the app/config import so settings pick these up.
os.environ.setdefault("DEVICE_TOKEN", "test-token")
os.environ.setdefault("AI_PROVIDER", "claude_cli")
# Point at a non-existent CLI so ClaudeCliProvider fails fast and uses its grounded
# fallback — tests stay deterministic and never invoke a real CLI.
os.environ.setdefault("CLAUDE_CLI_PATH", "/nonexistent/claude-cli-binary")
# Force OpenAI OFF in tests (overrides any key in the project .env) so the suite never
# makes a network call or spends credits. Integration tests can export a real key.
os.environ.setdefault("OPENAI_API_KEY", "")

from fastapi.testclient import TestClient  # noqa: E402

from qis.config import get_settings  # noqa: E402
from qis.main import create_app  # noqa: E402

TOKEN = "test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture(scope="session", autouse=True)
def _clear_settings_cache():
    get_settings.cache_clear()
    yield


@pytest.fixture
def client():
    with TestClient(create_app()) as c:
        yield c
