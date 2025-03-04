import json
import os
import tempfile
import base64
import whisper
import logging
import mimetypes
from urllib.parse import unquote

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Model configuration
MODEL_SIZE = os.environ.get("MODEL_SIZE", "tiny.en")

# Load the model - using the library's built-in caching mechanism
# The XDG_CACHE_HOME environment variable is set in the Dockerfile
# to point to the pre-downloaded model location
logger.info(f"Loading {MODEL_SIZE} model from cache")
model = whisper.load_model(MODEL_SIZE)

# Log where the model was loaded from for debugging
cache_dir = os.getenv("XDG_CACHE_HOME", os.path.join(os.path.expanduser("~"), ".cache"))
whisper_cache = os.path.join(cache_dir, "whisper")
logger.info(f"Using whisper cache directory: {whisper_cache}")
if os.path.exists(os.path.join(whisper_cache, f"{MODEL_SIZE}.pt")):
    logger.info(f"Found pre-downloaded model at {os.path.join(whisper_cache, f'{MODEL_SIZE}.pt')}")
else:
    logger.warning(f"Pre-downloaded model not found in {whisper_cache}")

# Map of common audio MIME types to file extensions
MIME_TO_EXT = {
    'audio/wav': '.wav',
    'audio/x-wav': '.wav',
    'audio/wave': '.wav',
    'audio/mp3': '.mp3',
    'audio/mpeg': '.mp3',
    'audio/ogg': '.ogg',
    'audio/flac': '.flac',
    'audio/x-flac': '.flac',
    'audio/m4a': '.m4a',
    'audio/x-m4a': '.m4a',
    'audio/mp4': '.m4a',
    'audio/x-mp4': '.m4a',
    'audio/aac': '.aac',
    'audio/webm': '.webm',
}

def get_file_extension(content_type=None, filename=None):
    """
    Determine the appropriate file extension based on content type or filename
    """
    # Try to get extension from content type
    if content_type and content_type in MIME_TO_EXT:
        return MIME_TO_EXT[content_type]
    
    # Try to get extension from filename if provided
    if filename:
        # Handle URL encoded filenames
        decoded_filename = unquote(filename)
        _, ext = os.path.splitext(decoded_filename)
        if ext:
            return ext
    
    # Default to .wav if we can't determine the type
    logger.info(f"Could not determine file extension from content_type: {content_type} or filename: {filename}. Using .wav")
    return '.wav'

def handler(event, context):
    """
    Lambda handler for Whisper transcription service
    """
    logger.info("Received event: %s", json.dumps(event))
    
    try:
        # Initialize variables for request processing
        audio_data = None
        content_type = None
        filename = None
        
        # Check if the request is from API Gateway
        if 'body' in event:
            # API Gateway request
            if event.get('isBase64Encoded', False):
                body = json.loads(base64.b64decode(event['body']))
            else:
                body = json.loads(event['body'])
            
            # Extract metadata and audio data
            if 'audio' in body:
                audio_data = base64.b64decode(body['audio'])
                content_type = body.get('contentType')
                filename = body.get('filename')
            else:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'No audio data provided'})
                }
        else:
            # Direct Lambda invocation
            if 'audio' in event:
                audio_data = base64.b64decode(event['audio'])
                content_type = event.get('contentType')
                filename = event.get('filename')
            else:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'No audio data provided'})
                }
        
        # Determine file extension
        file_ext = get_file_extension(content_type, filename)
        
        # Create a temporary file for the audio with the appropriate extension
        with tempfile.NamedTemporaryFile(suffix=file_ext, delete=False) as temp_audio:
            temp_audio.write(audio_data)
            temp_audio_path = temp_audio.name
        
        try:
            # Run transcription
            logger.info(f"Transcribing audio file with extension {file_ext} using {MODEL_SIZE} model")
            result = model.transcribe(temp_audio_path)
            
            # Extract transcription
            transcription = result['text']
            
            # Return response
            response = {
                'statusCode': 200,
                'body': json.dumps({
                    'transcription': transcription,
                    'model': MODEL_SIZE,
                    'fileType': file_ext[1:] if file_ext.startswith('.') else file_ext  # Remove leading dot
                })
            }
            
            logger.info(f"Transcription complete: {transcription[:50]}...")
            return response
            
        finally:
            # Clean up the temporary file
            if os.path.exists(temp_audio_path):
                os.remove(temp_audio_path)
                
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
