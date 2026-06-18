"""FastAPI application factory for the Quran Imam Shahid gateway."""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from qis import __version__
from qis.ai.provider import build_provider
from qis.config import get_settings
from qis.content.store import get_store
from qis.routes import health, quran, reason, voice
from qis.voice.speech import build_speech_engine


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    # Build the AI provider once (the migration seam) and warm the content store.
    app.state.provider = build_provider(settings)
    # Speech engine is None when no OpenAI key is configured (graceful degrade).
    app.state.speech = build_speech_engine(settings)
    get_store()
    yield


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="Quran Imam Shahid Gateway",
        version=__version__,
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.include_router(health.router)
    app.include_router(quran.router)
    app.include_router(reason.router)
    app.include_router(voice.router)
    return app


app = create_app()
