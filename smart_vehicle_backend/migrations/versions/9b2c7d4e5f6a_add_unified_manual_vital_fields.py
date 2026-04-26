"""add unified manual vital fields

Revision ID: 9b2c7d4e5f6a
Revises: 727f0a7dbc54

"""
from alembic import op
import sqlalchemy as sa


revision = "9b2c7d4e5f6a"
down_revision = "727f0a7dbc54"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("vitals", sa.Column("steps", sa.Integer(), nullable=True))
    op.add_column("vitals", sa.Column("calories", sa.Integer(), nullable=True))
    op.add_column("vitals", sa.Column("sleep", sa.Float(), nullable=True))


def downgrade():
    op.drop_column("vitals", "sleep")
    op.drop_column("vitals", "calories")
    op.drop_column("vitals", "steps")