from dataclasses import dataclass, field
from typing import Any

from pydantic import BaseModel

from app.schemas.capture import ParsedItem, ParseResult
from app.services.ai.providers import DEFAULT_MODELS, AIError


def parsed(type: str = "task", title: str = "Позвонить в банк", **fields: Any) -> ParsedItem:
    """ParsedItem с null во всех необязательных полях — как его вернул бы ИИ."""
    data: dict[str, Any] = {
        "type": type,
        "title": title,
        "details": None,
        "due_date": None,
        "due_time": None,
        "remind": False,
        "priority": "normal",
        "difficulty": None,
        "fact_category": None,
        "schedule_weekdays": None,
        "schedule_start": None,
        "schedule_end": None,
        "schedule_busy": None,
        "recurrence": None,
        "recurrence_weekdays": None,
        "mood": None,
        "energy": None,
        "tags": None,
        "products": None,
        "shopping_list": None,
    }
    data.update(fields)
    return ParsedItem.model_validate(data)


@dataclass
class FakeAI:
    """Подменяет провайдеров ИИ в тестах и запоминает, с чем их вызвали."""

    result: ParseResult = field(default_factory=lambda: ParseResult(items=[], reply="Ок"))
    error: str | None = None
    models: list[str] = field(default_factory=lambda: [DEFAULT_MODELS["gemini"], "gemini-x"])
    calls: list[dict[str, Any]] = field(default_factory=list)

    def respond(self, *items: ParsedItem, reply: str = "Понял") -> None:
        self.result = ParseResult(items=list(items), reply=reply)

    def factory(self, provider: str, api_key: str, model: str | None, timeout: float) -> Any:
        return _FakeProvider(self, provider, api_key, model or DEFAULT_MODELS[provider])


class _FakeProvider:
    def __init__(self, fake: FakeAI, name: str, api_key: str, model: str) -> None:
        self.fake, self.name, self.api_key, self.model = fake, name, api_key, model

    async def parse[T: BaseModel](self, instructions: str, text: str, schema: type[T]) -> T:
        self.fake.calls.append(
            {
                "provider": self.name,
                "api_key": self.api_key,
                "model": self.model,
                "instructions": instructions,
                "text": text,
            }
        )
        if self.fake.error:
            raise AIError(self.fake.error)
        return schema.model_validate(self.fake.result.model_dump())

    async def list_models(self) -> list[str]:
        if self.fake.error:
            raise AIError(self.fake.error)
        return self.fake.models
