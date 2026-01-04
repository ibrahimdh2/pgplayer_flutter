import json
import sys
import os
import traceback
import multiprocessing
import shutil
import tempfile
from pathlib import Path

# ==============================================
# CRITICAL: Multiprocessing guard for PyInstaller
# ==============================================
def is_main_process():
    """Check if this is the main process"""
    return __name__ == '__main__'

# Only set start method if we're the main process
if is_main_process():
    if sys.platform.startswith('win'):
        multiprocessing.freeze_support()
    else:
        try:
            multiprocessing.set_start_method('fork', force=True)
        except:
            pass

# Global variable to store persistent model path
PERSISTENT_MODEL_PATH = None

# Global detector instance for each worker
WORKER_DETECTOR = None

def find_bundled_model():
    """Find the model file in PyInstaller bundle"""
    if not getattr(sys, 'frozen', False):
        return None
    
    if not hasattr(sys, '_MEIPASS'):
        return None
    
    # Try multiple possible locations
    possible_paths = [
        os.path.join(sys._MEIPASS, 'nudenet', '320n.onnx'),
        os.path.join(sys._MEIPASS, '320n.onnx'),
        os.path.join(sys._MEIPASS, 'nudenet', 'nudenet', '320n.onnx'),
    ]
    
    print(f"Searching for model in _MEIPASS: {sys._MEIPASS}", file=sys.stderr)
    
    # Debug: List contents of _MEIPASS
    try:
        if os.path.exists(sys._MEIPASS):
            print(f"Contents of _MEIPASS:", file=sys.stderr)
            for item in os.listdir(sys._MEIPASS):
                item_path = os.path.join(sys._MEIPASS, item)
                if os.path.isdir(item_path):
                    print(f"  DIR: {item}/", file=sys.stderr)
                    # List subdirectories
                    try:
                        for subitem in os.listdir(item_path)[:5]:  # Show first 5 items
                            print(f"    - {subitem}", file=sys.stderr)
                    except:
                        pass
                else:
                    print(f"  FILE: {item}", file=sys.stderr)
    except Exception as e:
        print(f"Could not list _MEIPASS: {e}", file=sys.stderr)
    
    # Try each possible path
    for path in possible_paths:
        if os.path.exists(path):
            print(f"Found model at: {path}", file=sys.stderr)
            return path
    
    # Try to find it recursively
    try:
        for root, dirs, files in os.walk(sys._MEIPASS):
            if '320n.onnx' in files:
                found_path = os.path.join(root, '320n.onnx')
                print(f"Found model via recursive search: {found_path}", file=sys.stderr)
                return found_path
    except Exception as e:
        print(f"Error during recursive search: {e}", file=sys.stderr)
    
    return None

def copy_model_to_persistent_location():
    """Copy the model file to a persistent location that workers can access"""
    global PERSISTENT_MODEL_PATH
    
    if PERSISTENT_MODEL_PATH and os.path.exists(PERSISTENT_MODEL_PATH):
        return PERSISTENT_MODEL_PATH
    
    try:
        # Find the model in the PyInstaller bundle
        bundled_model = find_bundled_model()
        
        if bundled_model and os.path.exists(bundled_model):
            # Create a persistent temp directory
            persistent_dir = os.path.join(tempfile.gettempdir(), 'pgplayer_models')
            os.makedirs(persistent_dir, exist_ok=True)
            
            # Copy model to persistent location
            persistent_model = os.path.join(persistent_dir, '320n.onnx')
            
            if not os.path.exists(persistent_model):
                shutil.copy2(bundled_model, persistent_model)
                print(f"Copied model to persistent location: {persistent_model}", file=sys.stderr)
            else:
                print(f"Model already exists at: {persistent_model}", file=sys.stderr)
            
            PERSISTENT_MODEL_PATH = persistent_model
            return persistent_model
        
        # If not frozen or model not found, try to use package model
        if not getattr(sys, 'frozen', False):
            try:
                import nudenet
                package_model = os.path.join(os.path.dirname(nudenet.__file__), '320n.onnx')
                if os.path.exists(package_model):
                    PERSISTENT_MODEL_PATH = package_model
                    print(f"Using package model: {package_model}", file=sys.stderr)
                    return package_model
            except:
                pass
        
        print("Could not locate model file", file=sys.stderr)
        return None
        
    except Exception as e:
        print(f"Error copying model: {e}", file=sys.stderr)
        traceback.print_exc()
        return None

def update_progress(progress_path, completed):
    """Update progress file"""
    try:
        if progress_path and os.path.exists(os.path.dirname(progress_path)):
            with open(progress_path, 'w') as f:
                f.write(str(completed))
    except Exception as e:
        pass

def worker_initializer(model_path):
    """Initialize worker processes - runs once per worker"""
    global WORKER_DETECTOR
    
    try:
        from nudenet import NudeDetector
        
        if model_path and os.path.exists(model_path):
            print(f"Worker initializing with model: {model_path}", file=sys.stderr)
            WORKER_DETECTOR = NudeDetector(model_path=model_path)
        else:
            print(f"Worker initializing with default model", file=sys.stderr)
            WORKER_DETECTOR = NudeDetector()
        
        print("Worker detector initialized successfully", file=sys.stderr)
    except Exception as e:
        print(f"Error initializing worker detector: {e}", file=sys.stderr)
        traceback.print_exc()
        WORKER_DETECTOR = None

def analyze_frame_nudenet(frame_info, threshold):
    """Analyze frame using NudeNet with global detector"""
    global WORKER_DETECTOR
    
    try:
        if WORKER_DETECTOR is None:
            # Fallback: try to initialize detector in this process
            from nudenet import NudeDetector
            model_path = copy_model_to_persistent_location()
            
            if model_path:
                WORKER_DETECTOR = NudeDetector(model_path=model_path)
            else:
                WORKER_DETECTOR = NudeDetector()
        
        result = WORKER_DETECTOR.detect(frame_info['path'])
        nsfw_labels = ["FEMALE_GENITALIA_EXPOSED", "FEMALE_BREAST_EXPOSED", 
                       "MALE_GENITALIA_EXPOSED", "ANUS_EXPOSED", "BUTTOCKS_EXPOSED"]
        is_nsfw = any(item["class"] in nsfw_labels and item["score"] > threshold 
                     for item in result)
        
        return {
            'index': frame_info['index'],
            'timestamp': frame_info['timestamp'],
            'path': frame_info['path'],
            'isNSFW': is_nsfw
        }
    except Exception as e:
        print(f"Error analyzing frame {frame_info['index']}: {e}", file=sys.stderr)
        return {
            'index': frame_info['index'],
            'timestamp': frame_info['timestamp'],
            'path': frame_info['path'],
            'isNSFW': False
        }

def analyze_frame_nsfw_model(frame_info, threshold):
    """Analyze frame using NSFW Model"""
    try:
        from nsfw_detector import predict
        
        predictions = predict.classify(frame_info['path'])
        if frame_info['path'] in predictions:
            scores = predictions[frame_info['path']]
            nsfw_score = scores.get("porn", 0) + scores.get("hentai", 0)
            if threshold < 0.3:
                nsfw_score += scores.get("sexy", 0) * 0.5
            is_nsfw = nsfw_score > threshold
        else:
            is_nsfw = False
        
        return {
            'index': frame_info['index'],
            'timestamp': frame_info['timestamp'],
            'path': frame_info['path'],
            'isNSFW': is_nsfw
        }
    except Exception as e:
        print(f"Error analyzing frame {frame_info['index']}: {e}", file=sys.stderr)
        return {
            'index': frame_info['index'],
            'timestamp': frame_info['timestamp'],
            'path': frame_info['path'],
            'isNSFW': False
        }

def analyze_frame_clip(frame_info, threshold):
    """Analyze frame using CLIP"""
    try:
        import torch
        from transformers import CLIPProcessor, CLIPModel
        from PIL import Image
        
        model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
        processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
        
        nsfw_prompts = [
            "explicit nudity", "naked person", "sexual content", 
            "pornographic image", "intimate body parts",
            "suggestive pose", "revealing clothing"
        ]
        safe_prompts = ["normal clothed person", "safe content", "appropriate image"]
        
        image = Image.open(frame_info['path'])
        inputs = processor(images=image, return_tensors="pt")
        text_inputs = processor(text=nsfw_prompts + safe_prompts, return_tensors="pt", padding=True)
        
        with torch.no_grad():
            image_features = model.get_image_features(**inputs)
            text_features = model.get_text_features(**text_inputs)
            
            image_features = image_features / image_features.norm(dim=-1, keepdim=True)
            text_features = text_features / text_features.norm(dim=-1, keepdim=True)
            
            similarities = (image_features @ text_features.T).squeeze()
        
        nsfw_sim = similarities[:len(nsfw_prompts)].max().item()
        safe_sim = similarities[len(nsfw_prompts):].max().item()
        is_nsfw = nsfw_sim > safe_sim and nsfw_sim > threshold
        
        return {
            'index': frame_info['index'],
            'timestamp': frame_info['timestamp'],
            'path': frame_info['path'],
            'isNSFW': is_nsfw
        }
    except Exception as e:
        print(f"Error analyzing frame {frame_info['index']}: {e}", file=sys.stderr)
        return {
            'index': frame_info['index'],
            'timestamp': frame_info['timestamp'],
            'path': frame_info['path'],
            'isNSFW': False
        }

def worker_wrapper(args):
    """Worker function for multiprocessing"""
    try:
        frame_info, detector_type, threshold = args
        
        if detector_type == 'nudenet':
            result = analyze_frame_nudenet(frame_info, threshold)
        elif detector_type == 'nsfw_model':
            result = analyze_frame_nsfw_model(frame_info, threshold)
        elif detector_type == 'clip_interrogator':
            result = analyze_frame_clip(frame_info, threshold)
        else:
            result = {
                'index': frame_info['index'],
                'timestamp': frame_info['timestamp'],
                'path': frame_info['path'],
                'isNSFW': False
            }
        
        return result
    except Exception as e:
        print(f"Error in worker for frame {frame_info.get('index', 'unknown')}: {e}", file=sys.stderr)
        traceback.print_exc()
        return {
            'index': frame_info.get('index', 0),
            'timestamp': frame_info.get('timestamp', 0),
            'path': frame_info.get('path', ''),
            'isNSFW': False
        }

def process_frames_sequential(frames, detector_type, threshold, progress_path, model_path):
    """Process frames sequentially without multiprocessing"""
    worker_initializer(model_path)
    
    results = []
    for i, frame in enumerate(frames):
        result = worker_wrapper((frame, detector_type, threshold))
        results.append(result)
        
        if progress_path and (i + 1) % 5 == 0:
            update_progress(progress_path, i + 1)
    
    if progress_path:
        update_progress(progress_path, len(frames))
    
    return results

def process_frames_parallel(frames, detector_type, threshold, num_threads, progress_path, model_path):
    """Process frames in parallel using multiprocessing"""
    try:
        args_list = [(frame, detector_type, threshold) for frame in frames]
        
        print(f"Starting multiprocessing pool with {num_threads} workers...", file=sys.stderr)
        print(f"Model path: {model_path}", file=sys.stderr)
        
        with multiprocessing.Pool(
            processes=num_threads,
            initializer=worker_initializer,
            initargs=(model_path,)
        ) as pool:
            results = []
            
            chunk_size = max(1, len(frames) // (num_threads * 4))
            
            for i, result in enumerate(pool.imap_unordered(worker_wrapper, args_list, chunksize=chunk_size)):
                results.append(result)
                if progress_path and (i + 1) % 5 == 0:
                    update_progress(progress_path, i + 1)
            
            results.sort(key=lambda x: x['index'])
        
        if progress_path:
            update_progress(progress_path, len(frames))
        
        return results
        
    except Exception as e:
        print(f"Multiprocessing failed: {e}", file=sys.stderr)
        traceback.print_exc()
        print("Falling back to sequential processing...", file=sys.stderr)
        return process_frames_sequential(frames, detector_type, threshold, progress_path, model_path)

def main():
    try:
        import argparse
        
        print(f"Arguments received: {sys.argv}", file=sys.stderr)
        
        parser = argparse.ArgumentParser(description='NSFW Content Detector')
        parser.add_argument('-i', '--input', required=True, help='Input JSON configuration file')
        parser.add_argument('-o', '--output', required=True, help='Output results JSON file')
        parser.add_argument('--threshold', type=float, required=False, help='Detection threshold (optional)')
        
        args = parser.parse_args()
        
        input_json_path = args.input
        output_path = args.output
        
        print(f"Starting detector...", file=sys.stderr)
        print(f"Input: {input_json_path}", file=sys.stderr)
        print(f"Output: {output_path}", file=sys.stderr)
        
        # Copy model to persistent location BEFORE multiprocessing
        print("Preparing model...", file=sys.stderr)
        model_path = copy_model_to_persistent_location()
        
        if model_path:
            print(f"Model available at: {model_path}", file=sys.stderr)
        else:
            print("Warning: Could not locate model file, using default", file=sys.stderr)
        
        if not os.path.exists(input_json_path):
            print(f"Error: Input file does not exist: {input_json_path}", file=sys.stderr)
            sys.exit(1)
        
        try:
            with open(input_json_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except Exception as e:
            print(f"Error reading input JSON: {e}", file=sys.stderr)
            traceback.print_exc()
            sys.exit(1)
        
        frames = config.get('frames', [])
        detector_type = config.get('detector', 'nudenet')
        threshold = args.threshold if args.threshold is not None else config.get('threshold', 0.6)
        num_threads = config.get('threads', 4)
        result_path = output_path
        progress_path = config.get('progress_path', '')
        
        print(f"Detector: {detector_type}", file=sys.stderr)
        print(f"Threshold: {threshold}", file=sys.stderr)
        print(f"Threads: {num_threads}", file=sys.stderr)
        print(f"Frames to process: {len(frames)}", file=sys.stderr)
        
        if not frames:
            print("Warning: No frames to process", file=sys.stderr)
            with open(result_path, 'w', encoding='utf-8') as f:
                json.dump([], f)
            sys.exit(0)
        
        if progress_path:
            update_progress(progress_path, 0)
        
        if num_threads > 1:
            results = process_frames_parallel(frames, detector_type, threshold, num_threads, progress_path, model_path)
        else:
            results = process_frames_sequential(frames, detector_type, threshold, progress_path, model_path)
        
        print(f"Processing complete. Writing results to {result_path}...", file=sys.stderr)
        
        os.makedirs(os.path.dirname(os.path.abspath(result_path)), exist_ok=True)
        
        with open(result_path, 'w', encoding='utf-8') as f:
            json.dump(results, f, indent=2)
        
        if os.path.exists(result_path):
            file_size = os.path.getsize(result_path)
            print(f"Results file written successfully ({file_size} bytes)", file=sys.stderr)
        else:
            print(f"Error: Results file was not created!", file=sys.stderr)
            sys.exit(1)
        
        print("Detector completed successfully", file=sys.stderr)
        sys.exit(0)
        
    except Exception as e:
        print(f"Fatal error in main: {e}", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    if sys.platform.startswith('win'):
        multiprocessing.freeze_support()
    main()