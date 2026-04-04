import os
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def index():
    return jsonify({
        "app": "sample-app",
        "version": os.getenv("APP_VERSION", "1.0.0"),
        "environment": os.getenv("APP_ENV", "development"),
    })

@app.route("/health")
def health():
    return jsonify({"status": "healthy"})

@app.route("/ready")
def ready():
    return jsonify({"status": "ready"})

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
