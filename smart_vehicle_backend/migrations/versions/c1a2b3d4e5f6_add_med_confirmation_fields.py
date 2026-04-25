"""add med confirmation fields

Revision ID: c1a2b3d4e5f6
Revises: 9b2c7d4e5f6a

"""
from alembic import op
import sqlalchemy as sa


revision = "c1a2b3d4e5f6"
down_revision = "9b2c7d4e5f6a"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("med_reminders", sa.Column("last_confirmed_at", sa.DateTime(), nullable=True))
    op.add_column("med_reminders", sa.Column("last_confirmed_by", sa.String(length=100), nullable=True))
    op.add_column("med_reminders", sa.Column("pending_today", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("med_reminders", sa.Column("pending_date", sa.String(length=10), nullable=True))


def downgrade():
    op.drop_column("med_reminders", "pending_date")
    op.drop_column("med_reminders", "pending_today")
    op.drop_column("med_reminders", "last_confirmed_by")
    op.drop_column("med_reminders", "last_confirmed_at")