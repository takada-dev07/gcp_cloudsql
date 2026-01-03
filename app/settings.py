import os


def get_database_url() -> str | None:
    """
    STEP2で利用予定。STEP1ではFastAPI側からは未使用。
    """
    return os.getenv("DATABASE_URL")


