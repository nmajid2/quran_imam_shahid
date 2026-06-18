"""Gateway configuration. All secrets live here (on the box), never in the app."""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

Lang = Literal["fa", "en", "nl"]

# Project root (…/quran_imam_shahid). config.py lives at gateway/qis/config.py.
_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    # Load the project-root .env first, then a gateway-local .env (which overrides),
    # then real OS env vars (which override both). This lets the user keep one .env
    # with secrets at the repo root.
    model_config = SettingsConfigDict(
        env_file=(str(_ROOT / ".env"), str(_ROOT / "gateway" / ".env")),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Single-user auth: one long-lived device token the app sends as Bearer.
    device_token: str = "dev-token-change-me"

    # AI provider selection — the migration seam (claude_cli now, openai later).
    ai_provider: Literal["claude_cli", "openai"] = "claude_cli"
    claude_cli_path: str = "claude"

    # OpenAI — powers Whisper STT, TTS, and (optionally) the OpenAiProvider reasoning.
    openai_api_key: str = ""
    openai_chat_model: str = "gpt-4o"
    openai_whisper_model: str = "whisper-1"
    openai_tts_model: str = "gpt-4o-mini-tts"
    openai_tts_voice: str = "alloy"

    default_lang: Lang = "en"

    @property
    def openai_enabled(self) -> bool:
        return bool(self.openai_api_key.strip())

    # Comma-separated CORS origins for the web app.
    allowed_origins: str = "http://localhost:8080,http://localhost:3000"

    @property
    def cors_origins(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
