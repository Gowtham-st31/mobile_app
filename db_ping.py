import os
from urllib.parse import urlsplit, urlunsplit

from pymongo import MongoClient

# Optional local dev support: load environment variables from a .env file.
try:
    from dotenv import load_dotenv  # type: ignore

    load_dotenv()
except Exception:
    pass


def _redact_mongo_uri(uri: str) -> str:
    try:
        parts = urlsplit(uri)
        netloc = parts.netloc
        if "@" in netloc:
            _, hostinfo = netloc.rsplit("@", 1)
            netloc = f"<redacted>@{hostinfo}"
        return urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment))
    except Exception:
        return "<unavailable>"


def main() -> int:
    uri = os.getenv("MONGO_URI")
    if not uri:
        print("❌ MONGO_URI is not set")
        return 2

    print("Testing MongoDB connection...")
    print("MONGO_URI:", _redact_mongo_uri(uri))

    try:
        client = MongoClient(uri, serverSelectionTimeoutMS=5000, connectTimeoutMS=5000)
        client.admin.command("ping")
        print("✅ MongoDB ping OK")
        return 0
    except Exception as exc:
        print("❌ MongoDB ping FAILED")
        print(str(exc))
        return 1
    finally:
        try:
            client.close()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
