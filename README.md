# power_loom

## Local setup (Windows)

1. Create a virtual environment and install dependencies:
	- `python -m venv .venv`
	- `.\.venv\Scripts\Activate.ps1`
	- `pip install -r requirements.txt`

2. Configure environment variables:
	- Copy `.env.example` to `.env` and set `MONGO_URI`.
	- If you have MongoDB running locally, the default is `mongodb://localhost:27017`.

3. Run the server:
	- `python run_server.py`

## MongoDB notes

- The Flask app reads `MONGO_URI` from the environment (and will also read from a local `.env` file if present).
- Avoid committing real credentials to Git.