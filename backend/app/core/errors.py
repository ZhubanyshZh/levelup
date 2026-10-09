from fastapi import Request
from fastapi.responses import JSONResponse


class AppError(Exception):
    """Ошибка с машинным кодом: клиент показывает текст по коду на своём языке."""

    status_code = 400

    def __init__(self, code: str, status_code: int | None = None) -> None:
        super().__init__(code)
        self.code = code
        if status_code is not None:
            self.status_code = status_code


class AuthError(AppError):
    status_code = 401


async def app_error_handler(_: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, AppError)
    headers = {"WWW-Authenticate": "Bearer"} if exc.status_code == 401 else None
    return JSONResponse({"detail": exc.code}, status_code=exc.status_code, headers=headers)
