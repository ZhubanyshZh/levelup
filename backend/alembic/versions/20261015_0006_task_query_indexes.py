"""Indexes for bounded, filtered task pages.

Revision ID: 0006
Revises: 0005
"""

import sqlalchemy as sa

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None

INDEXES = [
    (
        "ix_tasks_live_due",
        [
            "user_id",
            sa.text("(CASE WHEN status = 'done' THEN 1 ELSE 0 END)"),
            sa.text("coalesce(due_date, DATE 'infinity')"),
            sa.text("coalesce(due_time, TIME '23:59:59')"),
            "position",
            "id",
        ],
        {},
    ),
    ("ix_tasks_live_date", ["user_id", "due_date"], {}),
    (
        "ix_tasks_open_due",
        [
            "user_id",
            sa.text("(CASE WHEN status = 'done' THEN 1 ELSE 0 END)"),
            sa.text("coalesce(due_date, DATE 'infinity')"),
            sa.text("coalesce(due_time, TIME '23:59:59')"),
            "position",
            "id",
        ],
        {"postgresql_where": sa.text("deleted_at IS NULL AND status != 'done'")},
    ),
    (
        "ix_tasks_done_completed",
        ["user_id", "completed_at"],
        {"postgresql_where": sa.text("deleted_at IS NULL AND status = 'done'")},
    ),
    (
        "ix_tasks_reminder_date",
        ["user_id", "due_date"],
        {"postgresql_where": sa.text("deleted_at IS NULL AND remind IS TRUE AND status != 'done'")},
    ),
    ("ix_tasks_live_status_position", ["user_id", "status", "position", "id"], {}),
    ("ix_tasks_live_priority", ["user_id", "priority"], {}),
    ("ix_tasks_live_sphere", ["user_id", "sphere"], {}),
    (
        "ix_tasks_live_search",
        [sa.text("lower(title || ' ' || coalesce(notes, '')) gin_trgm_ops")],
        {"postgresql_using": "gin"},
    ),
]


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    with op.get_context().autocommit_block():
        for name, columns, options in INDEXES:
            options.setdefault("postgresql_where", sa.text("deleted_at IS NULL"))
            valid = (
                None
                if op.get_context().as_sql
                else op.get_bind().scalar(
                    sa.text(
                        "SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid "
                        "WHERE c.relname = :name AND i.indrelid = 'tasks'::regclass"
                    ).bindparams(name=name)
                )
            )
            if valid is False:
                op.drop_index(name, table_name="tasks", postgresql_concurrently=True)
            op.create_index(
                name,
                "tasks",
                columns,
                postgresql_concurrently=True,
                if_not_exists=True,
                **options,
            )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        for name, _, _ in reversed(INDEXES):
            op.drop_index(name, table_name="tasks", postgresql_concurrently=True, if_exists=True)
