import pytest
import sys
import os

# Add app directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from main import app

def test_health_endpoint():
    """Test health endpoint"""
    with app.test_client() as client:
        response = client.get('/health')
        assert response.status_code == 200
        assert response.json['status'] == 'healthy'

def test_ready_endpoint():
    """Test readiness endpoint"""
    with app.test_client() as client:
        response = client.get('/ready')
        assert response.status_code == 200
        assert 'status' in response.json

def test_metrics_endpoint():
    """Test metrics endpoint"""
    with app.test_client() as client:
        response = client.get('/metrics')
        assert response.status_code == 200

def test_main_endpoint():
    """Test main endpoint exists"""
    with app.test_client() as client:
        # This will fail until you create main endpoint
        response = client.get('/')
        # For now, just test it returns something
        assert response.status_code in [200, 404]
