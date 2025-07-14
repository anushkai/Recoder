//
//  ContentView.swift
//  Recoder
//
//  Created by Anushka Idamekorala on 7/13/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var transcriber = ModernAudioTranscriber()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("System Audio Transcriber")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Transcribe system audio output in real-time")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                if transcriber.isRecording {
                    transcriber.stop()
                } else {
                    Task {
                        do {
                            try await transcriber.start()
                        } catch {
                            transcriber.errorMessage = error.localizedDescription
                        }
                    }
                }
            }) {
                HStack {
                    Image(systemName: transcriber.isRecording ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(transcriber.isRecording ? "Stop Recording" : "Start Recording")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(transcriber.isRecording ? Color.red : Color.blue)
                .cornerRadius(10)
            }
            .disabled(transcriber.errorMessage != nil)
            
            if let errorMessage = transcriber.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Transcription:")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                ScrollView {
                    Text(transcriber.transcription.isEmpty ? "No transcription yet..." : transcriber.transcription)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 300)
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            transcriber.setTranscriptionCallback { transcription in
                // This callback is called whenever transcription updates
                print("Transcription updated: \(transcription)")
            }
        }
    }
}

#Preview {
    ContentView()
}
