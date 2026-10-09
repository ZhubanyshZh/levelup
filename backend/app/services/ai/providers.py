"""Провайдеры ИИ. Модули к ним напрямую не обращаются — только через сервисы с ContextBuilder."""

from collections.abc import Callable
from typing import Protocol

import httpx
import openai
from google import genai
from google.genai import errors as genai_errors
from google.genai import types as genai_types
from pydantic import BaseModel, ValidationError

from app.core.errors import AppError

# Значения по умолчанию на октябрь 2026. Пользователь выбирает модель из списка,
# который отдаёт провайдер по его ключу, поэтому устаревание названий не ломает приложение.
DEFAULT_MODELS: dict[str, str] = {
    "gemini": "gemini-3.5-flash",
    "openai": "gpt-6-luna",
}


class AIError(AppError):
    """Ошибка провайдера ИИ. Коды: ai_not_configured, ai_invalid_key, ai_quota_exceeded,
    ai_rate_limited, ai_model_not_found, ai_bad_request, ai_unavailable, ai_bad_response."""

    status_code = 502


class AIProvider(Protocol):
    name: str
    model: str

    async def parse[T: BaseModel](self, instructions: str, text: str, schema: type[T]) -> T: ...

    async def list_models(self) -> list[str]: ...


ProviderFactory = Callable[[str, str, str | None, float], AIProvider]


class OpenAIProvider:
    name = "openai"

    def __init__(self, api_key: str, model: str, timeout: float) -> None:
        self.model = model
        self._client = openai.AsyncOpenAI(api_key=api_key, timeout=timeout, max_retries=1)

    async def parse[T: BaseModel](self, instructions: str, text: str, schema: type[T]) -> T:
        try:
            response = await self._client.responses.parse(
                model=self.model, instructions=instructions, input=text, text_format=schema
            )
        except openai.APIError as exc:
            raise _openai_error(exc) from exc
        if response.output_parsed is None:
            raise AIError("ai_bad_response")
        return response.output_parsed

    async def list_models(self) -> list[str]:
        try:
            ids = [model.id async for model in self._client.models.list()]
        except openai.APIError as exc:
            raise _openai_error(exc) from exc
        return sorted(model_id for model_id in ids if _is_openai_text_model(model_id))


class GeminiProvider:
    name = "gemini"

    def __init__(self, api_key: str, model: str, timeout: float) -> None:
        self.model = model
        self._client = genai.Client(
            api_key=api_key, http_options=genai_types.HttpOptions(timeout=int(timeout * 1000))
        )

    async def parse[T: BaseModel](self, instructions: str, text: str, schema: type[T]) -> T:
        config = genai_types.GenerateContentConfig(
            system_instruction=instructions,
            response_mime_type="application/json",
            response_schema=schema,
            temperature=0.2,
        )
        try:
            response = await self._client.aio.models.generate_content(
                model=self.model, contents=text, config=config
            )
        except (genai_errors.APIError, httpx.HTTPError) as exc:
            raise _gemini_error(exc) from exc
        if isinstance(response.parsed, schema):
            return response.parsed
        try:
            return schema.model_validate_json(response.text or "")
        except ValidationError as exc:
            raise AIError("ai_bad_response") from exc

    async def list_models(self) -> list[str]:
        try:
            pager = await self._client.aio.models.list()
            models = [model async for model in pager]
        except (genai_errors.APIError, httpx.HTTPError) as exc:
            raise _gemini_error(exc) from exc
        names = []
        for model in models:
            name = (model.name or "").removeprefix("models/")
            actions = model.supported_actions or []
            if "generateContent" in actions and _is_gemini_text_model(name):
                names.append(name)
        return sorted(names)


def create_provider(provider: str, api_key: str, model: str | None, timeout: float) -> AIProvider:
    model = model or DEFAULT_MODELS[provider]
    if provider == "openai":
        return OpenAIProvider(api_key, model, timeout)
    if provider == "gemini":
        return GeminiProvider(api_key, model, timeout)
    raise AIError("ai_not_configured", status_code=400)


def get_provider_factory() -> ProviderFactory:
    return create_provider


_EXCLUDED_MODEL_WORDS = (
    "audio",
    "realtime",
    "tts",
    "transcribe",
    "image",
    "embedding",
    "moderation",
    "search",
    "live",
    "veo",
    "imagen",
)


def _is_openai_text_model(model_id: str) -> bool:
    starts_ok = model_id.startswith("gpt-") or (model_id[:1] == "o" and model_id[1:2].isdigit())
    return starts_ok and not any(word in model_id for word in _EXCLUDED_MODEL_WORDS)


def _is_gemini_text_model(name: str) -> bool:
    return name.startswith("gemini") and not any(word in name for word in _EXCLUDED_MODEL_WORDS)


def _openai_error(exc: openai.APIError) -> AIError:
    if isinstance(exc, openai.AuthenticationError | openai.PermissionDeniedError):
        return AIError("ai_invalid_key")
    if isinstance(exc, openai.RateLimitError):
        quota = getattr(exc, "code", None) == "insufficient_quota"
        return AIError("ai_quota_exceeded" if quota else "ai_rate_limited")
    if isinstance(exc, openai.NotFoundError):
        return AIError("ai_model_not_found")
    if isinstance(exc, openai.BadRequestError):
        return AIError("ai_bad_request")
    return AIError("ai_unavailable")


def _gemini_error(exc: Exception) -> AIError:
    if isinstance(exc, genai_errors.ClientError):
        message = (exc.message or "").lower()
        if exc.code in (401, 403) or "api key" in message:
            return AIError("ai_invalid_key")
        if exc.code == 404:
            return AIError("ai_model_not_found")
        if exc.code == 429:
            return AIError("ai_rate_limited")
        return AIError("ai_bad_request")
    return AIError("ai_unavailable")
