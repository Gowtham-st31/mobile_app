from app import app, socketio


if __name__ == "__main__":
    # Run without the Flask reloader so the process stays stable (especially on Windows).
    socketio.run(app, host="0.0.0.0", port=8080, debug=True, use_reloader=False)
