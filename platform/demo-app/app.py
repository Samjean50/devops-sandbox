# Simple Flask app that runs inside each sandbox environment
# Every environment gets its own instance of this
from flask import Flask, jsonify
import os
import time

app = Flask(__name__)
START_TIME = time.time()

ENV_ID = os.getenv("ENV_ID", "unknown")
ENV_NAME = os.getenv("ENV_NAME", "unnamed")

@app.route("/")
def root():
    return jsonify({
        "message": f"Sandbox environment running",
        "env_id": ENV_ID,
        "env_name": ENV_NAME,
        "uptime_seconds": int(time.time() - START_TIME)
    })

@app.route("/health")
def health():
    return jsonify({
        "status": "ok",
        "env_id": ENV_ID,
        "uptime_seconds": int(time.time() - START_TIME)
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
