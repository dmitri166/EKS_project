import os
import sqlite3
import logging
import time
from datetime import datetime
from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Database path (default aligns with Helm PVC mountPath: /app/data)
DB_PATH = os.getenv("SQLITE_DB_PATH", "/app/data/tasks.db")

# Prometheus metrics
REQUEST_COUNT = Counter(
    "flask_requests_total", "Total requests", ["method", "endpoint", "status"]
)

REQUEST_DURATION = Histogram(
    "flask_request_duration_seconds",
    "Request duration in seconds",
    ["method", "endpoint"],
)

TASKS_TOTAL = Counter(
    "flask_tasks_total",
    "Total number of tasks",
    ["action"],  # action can be: created, updated, deleted
)


# Database setup
def init_db():
    """Initialize the SQLite database"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                description TEXT,
                done BOOLEAN NOT NULL DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.commit()
        conn.close()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
        raise


def get_db_connection():
    """Get database connection"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


# Middleware for metrics
@app.before_request
def before_request():
    request.start_time = time.time()


@app.after_request
def after_request(response):
    if hasattr(request, "start_time"):
        duration = time.time() - request.start_time
        REQUEST_DURATION.labels(
            method=request.method, endpoint=request.endpoint or "unknown"
        ).observe(duration)

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.endpoint or "unknown",
        status=response.status_code,
    ).inc()

    return response


# API Endpoints
@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    try:
        # Test database connection
        conn = get_db_connection()
        conn.execute("SELECT 1")
        conn.close()

        return (
            jsonify(
                {
                    "status": "healthy",
                    "timestamp": datetime.utcnow().isoformat(),
                    "version": "1.0.0",
                }
            ),
            200,
        )
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return (
            jsonify(
                {
                    "status": "unhealthy",
                    "timestamp": datetime.utcnow().isoformat(),
                    "error": str(e),
                }
            ),
            500,
        )


@app.route("/metrics", methods=["GET"])
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/tasks", methods=["GET"])
def get_tasks():
    """Get all tasks"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM tasks ORDER BY created_at DESC")
        tasks = cursor.fetchall()
        conn.close()

        tasks_list = []
        for task in tasks:
            tasks_list.append(
                {
                    "id": task["id"],
                    "title": task["title"],
                    "description": task["description"],
                    "done": bool(task["done"]),
                    "created_at": task["created_at"],
                    "updated_at": task["updated_at"],
                }
            )

        logger.info(f"Retrieved {len(tasks_list)} tasks")
        return jsonify({"tasks": tasks_list}), 200

    except Exception as e:
        logger.error(f"Error retrieving tasks: {e}")
        return jsonify({"error": "Internal server error"}), 500


@app.route("/tasks", methods=["POST"])
def create_task():
    """Create a new task"""
    try:
        data = request.get_json()

        if not data or "title" not in data:
            return jsonify({"error": "Title is required"}), 400

        title = data["title"].strip()
        description = data.get("description", "").strip()

        if not title:
            return jsonify({"error": "Title cannot be empty"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO tasks (title, description) VALUES (?, ?)", (title, description)
        )
        task_id = cursor.lastrowid
        conn.commit()
        conn.close()

        TASKS_TOTAL.labels(action="created").inc()
        logger.info(f"Created task with ID: {task_id}")

        return (
            jsonify(
                {
                    "id": task_id,
                    "title": title,
                    "description": description,
                    "done": False,
                    "message": "Task created successfully",
                }
            ),
            201,
        )

    except Exception as e:
        logger.error(f"Error creating task: {e}")
        return jsonify({"error": "Internal server error"}), 500


@app.route("/tasks/<int:task_id>", methods=["PUT"])
def update_task(task_id):
    """Update task status"""
    try:
        data = request.get_json()

        if not data or "done" not in data:
            return jsonify({"error": "Done status is required"}), 400

        if not isinstance(data["done"], bool):
            return jsonify({"error": "Done status must be boolean"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        # Check if task exists
        cursor.execute("SELECT id FROM tasks WHERE id = ?", (task_id,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({"error": "Task not found"}), 404

        # Update task
        cursor.execute(
            "UPDATE tasks SET done = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (data["done"], task_id),
        )
        conn.commit()
        conn.close()

        TASKS_TOTAL.labels(action="updated").inc()
        logger.info(f"Updated task {task_id} status to {data['done']}")

        return (
            jsonify(
                {
                    "id": task_id,
                    "done": data["done"],
                    "message": "Task updated successfully",
                }
            ),
            200,
        )

    except Exception as e:
        logger.error(f"Error updating task {task_id}: {e}")
        return jsonify({"error": "Internal server error"}), 500


@app.route("/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    """Delete a task"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Check if task exists
        cursor.execute("SELECT id FROM tasks WHERE id = ?", (task_id,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({"error": "Task not found"}), 404

        # Delete task
        cursor.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
        conn.commit()
        conn.close()

        TASKS_TOTAL.labels(action="deleted").inc()
        logger.info(f"Deleted task {task_id}")

        return (
            jsonify({"id": task_id, "message": "Task deleted successfully"}),
            200,
        )

    except Exception as e:
        logger.error(f"Error deleting task {task_id}: {e}")
        return jsonify({"error": "Internal server error"}), 500


# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Endpoint not found"}), 404


@app.errorhandler(405)
def method_not_allowed(error):
    return jsonify({"error": "Method not allowed"}), 405


@app.errorhandler(500)
def internal_error(error):
    logger.error(f"Internal server error: {error}")
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    # Initialize database
    init_db()

    # Get configuration from environment
    host = os.getenv("FLASK_HOST", "0.0.0.0")
    port = int(os.getenv("FLASK_PORT", 5000))
    debug = os.getenv("FLASK_DEBUG", "False").lower() == "true"

    logger.info(f"Starting Flask app on {host}:{port}")
    app.run(host=host, port=port, debug=debug)
