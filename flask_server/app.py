from flask import Flask, request, jsonify
from ultralytics import YOLO
from PIL import Image
import os
import gdown
import time

app = Flask(__name__)

model_path = "best.pt"
gdrive_file_id = "1cvke7f2M56xvPWPd5AGMXb14zzFiUG43"

if not os.path.exists(model_path):
    print("Downloading YOLOv8 model...")
    gdown.download(f"https://drive.google.com/uc?id={gdrive_file_id}", model_path, quiet=False)

try:
    model = YOLO(model_path)
except Exception as e:
    print(f"Failed to load YOLO model: {e}")
    model = None

@app.route("/predict", methods=["POST"])
def predict():
    if model is None:
        return jsonify({"error": "Model not loaded"}), 500

    if 'image' not in request.files:
        return jsonify({"error": "No image uploaded"}), 400

    try:
        image_file = request.files['image']
        image = Image.open(image_file.stream).convert("RGB")

        # 🔧 Improve inference accuracy
        results = model(image, conf=0.38, iou=0.5, imgsz=640, augment=True)  # Enable TTA

        output = []
        for r in results:
            for box in r.boxes:
                class_id = int(box.cls[0])
                class_name = r.names[class_id]
                confidence = float(box.conf[0])
                bbox = list(map(float, box.xyxy[0].tolist()))

                # Filter very small boxes (noise)
                area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
                if area < 800:  # Skip tiny detections
                    continue

                output.append({
                    "class": class_name,
                    "confidence": round(confidence, 2),
                    "bbox": bbox
                })

        # 🔽 Sort detections by confidence (high to low)
        output.sort(key=lambda x: x["confidence"], reverse=True)

        return jsonify({"detections": output})

    except Exception as e:
        print(f"Error during prediction: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
