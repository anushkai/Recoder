# Recoder - Audio Transcription App

A macOS app that transcribes system audio output in real-time using Apple's Speech Recognition framework.

## Features

- Real-time transcription of system audio output
- Modern SwiftUI interface
- Start/stop recording with a single button click
- Live transcription display
- Error handling and permission management
- Clear transcription results

## Requirements

- macOS 12.3 or later
- Microphone access permission
- Screen recording permission (for system audio capture)

## Setup and Usage

1. **Build and Run**: Open the project in Xcode and build it
2. **Grant Permissions**: When you first run the app, you'll need to grant:
   - Microphone access (for audio input)
   - Screen recording permission (for system audio capture)
3. **Start Recording**: Click the "Start Recording" button to begin transcription
4. **View Results**: The transcription will appear in real-time in the results window
5. **Stop Recording**: Click "Stop Recording" to end the transcription session

## Permissions Required

The app requires the following permissions to function:

- **Microphone Access**: Required to capture system audio output
- **Screen Recording**: Required to access system audio through ScreenCaptureKit
- **Speech Recognition**: Automatically requested when the app starts

## Technical Details

- Uses `ScreenCaptureKit` for system audio capture
- Uses `Speech` framework for real-time transcription
- Built with SwiftUI for modern macOS interface
- Supports macOS 12.3+ for ScreenCaptureKit compatibility

## Troubleshooting

If you encounter issues:

1. **Permission Denied**: Make sure to grant microphone and screen recording permissions in System Preferences > Security & Privacy
2. **No Audio**: Ensure your system is playing audio and the app has screen recording permission
3. **Transcription Not Working**: Check that Speech Recognition is enabled in System Preferences

## Development

The app is built with:
- SwiftUI for the user interface
- ScreenCaptureKit for audio capture
- Speech framework for transcription
- Modern async/await patterns for concurrency

## License

This project is for educational and personal use. 