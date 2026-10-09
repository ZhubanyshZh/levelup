from datetime import UTC, datetime, timedelta

from httpx import AsyncClient

from app.services.workouts import exercise_key
from tests.conftest import bearer, sign_in_device


def _day(offset: int) -> str:
    return (datetime.now(UTC).date() + timedelta(days=offset)).isoformat()


async def _workout(client: AsyncClient, tokens: dict, sets: list[dict], day: int = 0) -> dict:
    response = await client.post(
        "/workouts",
        headers=bearer(tokens),
        json={"workout_date": _day(day), "sets": sets},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _bench(weight: float, reps: int = 5) -> dict:
    return {"exercise": "Жим лёжа", "weight_kg": weight, "reps": reps}


async def test_first_workout_is_a_baseline_not_a_record(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    result = await _workout(client, tokens, [_bench(80), _bench(80)], day=-2)

    assert result["records"] == []
    assert result["xp_gained"] == 25
    assert not any(s["is_pr"] for s in result["workout"]["sets"])


async def test_heavier_set_is_a_personal_record(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _workout(client, tokens, [_bench(80)], day=-2)

    result = await _workout(client, tokens, [_bench(80), _bench(85, 3), _bench(82.5)], day=0)

    assert result["records"] == ["Жим лёжа"]
    assert [s["is_pr"] for s in result["workout"]["sets"]] == [False, True, False]
    # 25 за тренировку + 50 за рекорд.
    assert result["xp_gained"] == 75


async def test_bodyweight_and_timed_records(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _workout(
        client,
        tokens,
        [{"exercise": "Подтягивания", "reps": 10}, {"exercise": "Планка", "duration_sec": 60}],
        day=-1,
    )

    result = await _workout(
        client,
        tokens,
        [{"exercise": "подтягивания", "reps": 12}, {"exercise": "Планка", "duration_sec": 50}],
    )

    assert result["records"] == ["подтягивания"]


async def test_only_two_workouts_a_day_give_xp(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)

    gained = [
        (await _workout(client, tokens, [{"exercise": "Бег", "distance_m": 1000}]))["xp_gained"]
        for _ in range(3)
    ]

    assert gained == [25, 25, 0]


async def test_deleting_workout_takes_xp_back(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _workout(client, tokens, [_bench(80)], day=-1)
    result = await _workout(client, tokens, [_bench(90)])

    await client.delete(f"/workouts/{result['workout']['id']}", headers=bearer(tokens))

    progress = (await client.get("/progress", headers=bearer(tokens))).json()
    types = [e["source_type"] for e in progress["recent"] if e["source_type"] != "quest"]
    assert types == ["workout"]


async def test_editing_sets_recomputes_record(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _workout(client, tokens, [_bench(80)], day=-1)
    result = await _workout(client, tokens, [_bench(90)])

    edited = (
        await client.patch(
            f"/workouts/{result['workout']['id']}",
            headers=bearer(tokens),
            json={"sets": [_bench(70)]},
        )
    ).json()

    assert edited["records"] == []
    progress = (await client.get("/progress", headers=bearer(tokens))).json()
    assert "pr" not in [e["source_type"] for e in progress["recent"]]


async def test_editing_earlier_workout_keeps_its_record(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _workout(client, tokens, [_bench(80)], day=-2)
    record = await _workout(client, tokens, [_bench(85)], day=-1)
    await _workout(client, tokens, [_bench(90)], day=-1)

    edited = await client.patch(
        f"/workouts/{record['workout']['id']}",
        headers=bearer(tokens),
        json={"note": "Хороший день"},
    )

    assert edited.status_code == 200, edited.text
    assert edited.json()["records"] == ["Жим лёжа"]
    assert edited.json()["workout"]["sets"][0]["is_pr"] is True


async def test_exercise_stats_show_history(client: AsyncClient) -> None:
    tokens = await sign_in_device(client)
    await _workout(client, tokens, [_bench(80), _bench(80)], day=-3)
    await _workout(client, tokens, [_bench(85)], day=-1)

    stats = (await client.get("/workouts/exercises", headers=bearer(tokens))).json()

    bench = stats[0]
    assert bench["name"] == "Жим лёжа"
    assert bench["sessions"] == 2
    assert bench["best_weight_kg"] == 85
    assert [p["volume_kg"] for p in bench["history"]] == [800, 425]


def test_exercise_names_are_normalized() -> None:
    assert exercise_key(" Жим  лёжа! ") == exercise_key("жим лежа")
