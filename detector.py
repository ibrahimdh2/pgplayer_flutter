import json
import sys
import os
import traceback
import multiprocessing
from pathlib import Path

def update_progress(progress_path, completed):
    """Update progress file"""
    try:
        with open(progress_path, 'w') as f:
            f.write(str(completed))
    except Exception as e:
        print(f"Warning: Could not update progress: {e}", file=sys.stderr)

def analyze_frame_nudenet(frame_info, threshold):
    """Analyze frame using NudeNet"""
    try:
        from nudenet import NudeDetector
        detector = NudeDetector()
        
        result = detector.detect(frame_info['path'])
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
    frame_info, detector_type, threshold, progress_queue = args
    
    try:
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
        
        progress_queue.put(1)
        return result
    except Exception as e:
        print(f"Error in worker for frame {frame_info['index']}: {e}", file=sys.stderr)
        traceback.print_exc()
        return {
            'index': frame_info['index'],
            'timestamp': frame_info['timestamp'],
            'path': frame_info['path'],
            'isNSFW': False
        }

def main():
    try:
        import argparse
        
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
        
        # Verify input file exists
        if not os.path.exists(input_json_path):
            print(f"Error: Input file does not exist: {input_json_path}", file=sys.stderr)
            sys.exit(1)
        
        # Read input configuration
        try:
            with open(input_json_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except Exception as e:
            print(f"Error reading input JSON: {e}", file=sys.stderr)
            traceback.print_exc()
            sys.exit(1)
        
        frames = config.get('frames', [])
        detector_type = config.get('detector', 'nudenet')
        threshold = args.threshold if args.threshold else config.get('threshold', 0.6)
        num_threads = config.get('threads', 4)
        result_path = output_path
        progress_path = config.get('progress_path', '')
        
        print(f"Detector: {detector_type}", file=sys.stderr)
        print(f"Threshold: {threshold}", file=sys.stderr)
        print(f"Threads: {num_threads}", file=sys.stderr)
        print(f"Frames to process: {len(frames)}", file=sys.stderr)
        
        if not frames:
            print("Warning: No frames to process", file=sys.stderr)
            # Write empty results
            with open(result_path, 'w', encoding='utf-8') as f:
                json.dump([], f)
            sys.exit(0)
        
        # Create progress file
        if progress_path:
            update_progress(progress_path, 0)
        
        # Use multiprocessing Pool
        manager = multiprocessing.Manager()
        progress_queue = manager.Queue()
        
        # Prepare arguments with progress queue
        args_list = [(frame, detector_type, threshold, progress_queue) for frame in frames]
        
        # Track progress
        completed = 0
        
        print("Starting multiprocessing pool...", file=sys.stderr)
        
        with multiprocessing.Pool(processes=num_threads) as pool:
            results = []
            async_results = pool.map_async(worker_wrapper, args_list)
            
            # Update progress while waiting
            while not async_results.ready():
                try:
                    while not progress_queue.empty():
                        progress_queue.get()
                        completed += 1
                        if progress_path:
                            update_progress(progress_path, completed)
                except:
                    pass
                async_results.wait(0.5)
            
            results = async_results.get()
        
        print(f"Processing complete. Writing results to {result_path}...", file=sys.stderr)
        
        # Write results
        with open(result_path, 'w', encoding='utf-8') as f:
            json.dump(results, f, indent=2)
        
        # Verify file was written
        if os.path.exists(result_path):
            file_size = os.path.getsize(result_path)
            print(f"Results file written successfully ({file_size} bytes)", file=sys.stderr)
        else:
            print(f"Error: Results file was not created!", file=sys.stderr)
            sys.exit(1)
        
        if progress_path:
            update_progress(progress_path, len(frames))
        
        print("Detector completed successfully", file=sys.stderr)
        
    except Exception as e:
        print(f"Fatal error in main: {e}", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    multiprocessing.freeze_support()  # Required for PyInstaller
    main()