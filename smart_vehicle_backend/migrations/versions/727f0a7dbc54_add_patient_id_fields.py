"""add patient_id fields

Revision ID: 727f0a7dbc54
Revises: 

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '727f0a7dbc54'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # users.patient_id
    op.add_column('users', sa.Column('patient_id', sa.Integer(), nullable=True))
    op.create_index('ix_users_patient_id', 'users', ['patient_id'], unique=True)

    # vitals.patient_id
    op.add_column('vitals', sa.Column('patient_id', sa.Integer(), nullable=True))
    op.create_index('ix_vitals_patient_id', 'vitals', ['patient_id'], unique=False)

    # fall_event.patient_id
    op.add_column('fall_event', sa.Column('patient_id', sa.Integer(), nullable=True))
    op.create_index('ix_fall_event_patient_id', 'fall_event', ['patient_id'], unique=False)


def downgrade():
    op.drop_index('ix_fall_event_patient_id', table_name='fall_event')
    op.drop_column('fall_event', 'patient_id')

    op.drop_index('ix_vitals_patient_id', table_name='vitals')
    op.drop_column('vitals', 'patient_id')

    op.drop_index('ix_users_patient_id', table_name='users')
    op.drop_column('users', 'patient_id')