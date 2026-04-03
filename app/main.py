import logging
import os
import time
from datetime import datetime

from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from prometheus_client import (
    Counter,
    CONTENT_TYPE_LATEST,
    generate_latest,
    Histogram,
)
import redis

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Database configuration
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:////app/data/tasks.db")
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)

# Redis configuration
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", None)

try:
    cache = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, decode_responses=True)
    cache.ping()
    logger.info("Connected to Redis successfully")
except Exception as e:
    logger.warning(f"Could not connect to Redis: {e}")
    cache = None

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

# Database Model
class Task(db.Model):
    __tablename__ = 'tasks'
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(255), nullable=False)
    description = db.Column(db.Text)
    done = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "done": self.done,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }

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
        db.session.execute(db.text("SELECT 1"))
        
        # Test Redis connection if available
        redis_status = "connected" if cache and cache.ping() else "disconnected"

        return (
            jsonify(
                {
                    "status": "healthy",
                    "database": "connected",
                    "redis": redis_status,
                    "timestamp": datetime.utcnow().isoformat(),
                    "version": "2.0.0",
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
        # Try to get from cache first
        if cache:
            cached_tasks = cache.get("tasks_list")
            if cached_tasks:
                logger.info("Retrieved tasks from cache")
                import json
                return jsonify({"tasks": json.loads(cached_tasks), "source": "cache"}), 200

        tasks = Task.query.order_by(Task.created_at.desc()).all()
        tasks_list = [task.to_dict() for task in tasks]
        
        # Update cache
        if cache:
            import json
            cache.setex("tasks_list", 60, json.dumps(tasks_list))
            logger.info("Updated tasks cache")

        logger.info(f"Retrieved {len(tasks_list)} tasks from DB")
        return jsonify({"tasks": tasks_list, "source": "database"}), 200

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

        new_task = Task(title=title, description=description)
        db.session.add(new_task)
        db.session.commit()

        # Invalidate cache
        if cache:
            cache.delete("tasks_list")

        TASKS_TOTAL.labels(action="created").inc()
        logger.info(f"Created task with ID: {new_task.id}")

        return (
            jsonify(
                {
                    "id": new_task.id,
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

        task = Task.query.get(task_id)
        if not task:
            return jsonify({"error": "Task not found"}), 404

        task.done = data["done"]
        db.session.commit()

        # Invalidate cache
        if cache:
            cache.delete("tasks_list")

        TASKS_TOTAL.labels(action="updated").inc()
        logger.info(f"Updated task {task_id} status to {task.done}")

        return (
            jsonify(
                {
                    "id": task_id,
                    "done": task.done,
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
        task = Task.query.get(task_id)
        if not task:
            return jsonify({"error": "Task not found"}), 404

        db.session.delete(task)
        db.session.commit()

        # Invalidate cache
        if cache:
            cache.delete("tasks_list")

        TASKS_TOTAL.labels(action="deleted").inc()
        logger.info(f"Deleted task {task_id}")

        return (
            jsonify({"id": task_id, "message": "Task deleted successfully"}),
            200,
        )

    except Exception as e:
        logger.error(f"Error deleting task {task_id}: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/ready')
def ready():
    """Readiness check endpoint for Kubernetes readiness probe"""
    try:
        db.session.execute(db.text("SELECT 1"))
        return jsonify({
            'status': 'ready',
            'database': 'connected',
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return jsonify({
            'status': 'not ready',
            'database': 'disconnected',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 503

if __name__ == "__main__":
    with app.app_context():
        db.create_all()

    host = os.getenv("FLASK_HOST", "0.0.0.0")
    port = int(os.getenv("FLASK_PORT", 5000))
    debug = os.getenv("FLASK_DEBUG", "False").lower() == "true"

    logger.info(f"Starting Flask app v2.0 on {host}:{port}")
    app.run(host=host, port=port, debug=debug)
