# YOLOv8 Flask API

This API uses YOLOv8 with a Flask server to detect objects in uploaded images.

## Usage
- POST an image to `/predict`
- Returns JSON with class, confidence, and bounding box

## Setup
```bash
pip install -r requirements.txt
python app.py
```

Model (`best.pt`) is auto-downloaded from Google Drive.
