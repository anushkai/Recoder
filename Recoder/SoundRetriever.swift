
import AVFoundation
import ScreenCaptureKit
import Speech
import CoreVideo

// Available on macOS 12.3+
@available(macOS 12.3, *)
class ModernAudioTranscriber: NSObject, ObservableObject, SCStreamOutput {
    @Published var isRecording = false
    @Published var transcription = ""
    @Published var errorMessage: String?
    
    private var stream: SCStream?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onTranscriptionUpdate: ((String) -> Void)?
    
    func setTranscriptionCallback(_ callback: @escaping (String) -> Void) {
        print("[LOG] Setting transcription callback")
        onTranscriptionUpdate = callback
    }
    
    func start() async throws {
        print("[LOG] Starting ModernAudioTranscriber.start()")
        // Check speech recognition permissions
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        print("[LOG] Speech recognizer authorization status: \(speechAuth.rawValue)")
        if speechAuth != .authorized {
            print("[LOG] Requesting speech recognition permission...")
            await requestSpeechPermission()
            let newStatus = SFSpeechRecognizer.authorizationStatus()
            print("[LOG] Speech recognizer authorization status after request: \(newStatus.rawValue)")
            if newStatus != .authorized {
                await MainActor.run { self.errorMessage = "Speech recognition permission denied" }
                print("[ERROR] Speech recognition permission denied")
                throw TranscriptionError.permissionDenied
            }
        }
        
        // Check screen recording permissions
        print("[LOG] Checking screen recording permission...")
        if !checkScreenRecordingPermission() {
            print("[LOG] Requesting screen recording permission...")
            let granted = await requestScreenRecordingPermission()
            print("[LOG] Screen recording permission granted: \(granted)")
            if !granted {
                await MainActor.run { 
                    self.errorMessage = "Screen recording permission denied. Please enable it in System Settings > Privacy & Security > Screen Recording."
                }
                print("[ERROR] Screen recording permission denied")
                throw TranscriptionError.screenRecordingDenied
            }
        }
        
        print("[LOG] Getting shareable content...")
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
            print("[LOG] SCShareableContent.current succeeded. Displays found: \(content.displays.count)")
        } catch {
            print("[ERROR] Failed to get SCShareableContent.current: \(error)")
            await MainActor.run { self.errorMessage = "Failed to get shareable content: \(error.localizedDescription)" }
            throw error
        }
        
        guard let mainDisplay = content.displays.first else {
            await MainActor.run { self.errorMessage = "No displays found to capture audio from." }
            print("[ERROR] No displays found to capture audio from.")
            throw TranscriptionError.noDisplaysFound
        }
        print("[LOG] Using display: \(mainDisplay.frame)")
        
        // Configure the stream to capture ONLY audio.
        let filter = SCContentFilter(display: mainDisplay, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
    
        config.pixelFormat = kCVPixelFormatType_32ARGB
        config.width = 1
        config.height = 1
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)


        print("[LOG] Creating SCStream with filter and config...")
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        
        // Check if stream creation failed
        guard let stream = stream else {
            await MainActor.run { 
                self.errorMessage = "Failed to create screen capture stream. This usually means screen recording permission is not granted or the system doesn't support screen capture."
            }
            print("[ERROR] Failed to create SCStream (stream is nil)")
            throw TranscriptionError.streamCreationFailed
        }
        print("[LOG] SCStream created successfully")
        
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
            print("[LOG] Stream output added successfully")
        } catch {
            await MainActor.run { self.errorMessage = "Failed to add stream output: \(error.localizedDescription)" }
            print("[ERROR] Failed to add stream output: \(error)")
            throw TranscriptionError.streamError
        }
        
        print("[LOG] Setting up and starting speech recognition...")
        setupAndStartSpeechRecognition()
        
        do {
            print("[LOG] Starting stream capture...")
            try await stream.startCapture()
            print("[LOG] Capture started successfully")
        } catch {
            print("[ERROR] Failed to start capture: \(error)")
            await MainActor.run { self.errorMessage = "Failed to start stream: \(error.localizedDescription)" }
            throw TranscriptionError.streamError
        }
        
        await MainActor.run {
            self.isRecording = true
            self.errorMessage = nil
        }
        print("[LOG] Modern transcriber started successfully.")
    }
    
    func stop() {
        print("[LOG] Stopping ModernAudioTranscriber...")
        Task {
            try? await stream?.stopCapture()
            recognitionTask?.cancel()
            stream = nil
            recognitionTask = nil
            recognitionRequest = nil
            await MainActor.run {
                self.isRecording = false
            }
            print("[LOG] Modern transcriber stopped.")
        }
    }
    // This delegate method receives the audio sample buffers from the system.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else {
            print("[WARN] Received invalid or non-audio sample buffer.")
            return
        }
        
        // Log audio buffer info
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        print("[LOG] Received audio buffer with \(frameCount) frames")
        
        if let buffer = convertToAudioBuffer(from: sampleBuffer) {
            print("[LOG] Successfully converted to AVAudioPCMBuffer")
            print("[LOG] Audio format: \(buffer.format), channels: \(buffer.format.channelCount), sample rate: \(buffer.format.sampleRate)")
            print("[LOG] Frame length: \(buffer.frameLength), frame capacity: \(buffer.frameCapacity)")
            
            // Check if audio has actual content (not silent)
            if let channelData = buffer.floatChannelData?.pointee {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
                let maxAmplitude = samples.map { abs($0) }.max() ?? 0
                print("[LOG] Audio amplitude: \(maxAmplitude)")
            }
            
            recognitionRequest?.append(buffer)
        } else {
            print("[ERROR] Failed to convert CMSampleBuffer to AVAudioPCMBuffer.")
        }
    }
    
    private func convertToAudioBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("[ERROR] CMSampleBufferGetFormatDescription failed.")
            return nil
        }
        let audioFormat = AVAudioFormat(cmAudioFormatDescription: format)
        let frameCount = UInt32(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            print("[ERROR] Failed to create AVAudioPCMBuffer.")
            return nil
        }
        audioBuffer.frameLength = frameCount
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("[ERROR] CMSampleBufferGetDataBuffer failed.")
            return nil
        }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else {
            print("[ERROR] CMBlockBufferGetDataPointer failed with status: \(status)")
            return nil
        }
        let audioData = Data(bytes: dataPointer, count: length)
        if let channelData = audioBuffer.int16ChannelData?.pointee {
            let destPointer = UnsafeMutableRawPointer(mutating: channelData)
            audioData.copyBytes(to: destPointer.assumingMemoryBound(to: UInt8.self), count: length)
        }
        return audioBuffer
    }
    private func setupAndStartSpeechRecognition() {
        print("[LOG] Setting up SFSpeechAudioBufferRecognitionRequest and recognitionTask...")
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest!.shouldReportPartialResults = true
        
        // Configure for better speech detection
        recognitionRequest!.taskHint = .dictation
        recognitionRequest!.contextualStrings = ["hello", "test", "speech", "recognition"]
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self = self else { return }
            var isFinal = false
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcription = text
                    self.onTranscriptionUpdate?(text)
                }
                isFinal = result.isFinal
            }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Recognition error: \(error.localizedDescription)"
                }
                print("[ERROR] Speech recognition error: \(error)")
                print("[ERROR] Error domain: \(error._domain), code: \(error._code)")
                if let userInfo = error._userInfo {
                    print("[ERROR] Error user info: \(userInfo)")
                }
            }
            if error != nil || isFinal {
                print("[LOG] Recognition task ended. Restarting if stream is active...")
                self.recognitionTask?.cancel()
                if self.stream != nil {
                    self.setupAndStartSpeechRecognition()
                }
            }
        }
    }
    private func requestSpeechPermission() async {
        print("[LOG] Requesting speech permission...")
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                print("[LOG] SpeechRecognizer.requestAuthorization returned status: \(status.rawValue)")
                continuation.resume()
            }
        }
    }
    
    private func checkScreenRecordingPermission() -> Bool {
        let hasPermission = CGPreflightScreenCaptureAccess()
        print("[LOG] CGPreflightScreenCaptureAccess returned: \(hasPermission)")
        if !hasPermission {
            print("[WARN] Screen recording permission not granted")
            return false
        }
        print("[LOG] Screen recording permission granted")
        return true
    }
    
    private func requestScreenRecordingPermission() async -> Bool {
        print("[LOG] Requesting screen recording permission via CGRequestScreenCaptureAccess...")
        return await withCheckedContinuation { continuation in
            let granted = CGRequestScreenCaptureAccess()
            print("[LOG] CGRequestScreenCaptureAccess returned: \(granted)")
            continuation.resume(returning: granted)
        }
    }
    enum TranscriptionError: Error, LocalizedError {
        case permissionDenied
        case noDisplaysFound
        case streamError
        case streamCreationFailed
        case screenRecordingDenied
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Speech recognition permission denied"
            case .noDisplaysFound:
                return "No displays found for audio capture"
            case .streamError:
                return "Failed to start audio stream"
            case .streamCreationFailed:
                return "Failed to create screen capture stream. This usually means screen recording permission is not granted or the system doesn't support screen capture."
            case .screenRecordingDenied:
                return "Screen recording permission denied. Please enable it in System Settings > Privacy & Security > Screen Recording."
            }
        }
    }
}