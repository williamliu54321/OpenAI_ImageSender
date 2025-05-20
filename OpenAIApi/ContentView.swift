import Foundation
import SwiftUI
import AVFoundation

final class APICaller {
    static let shared = APICaller()

    @frozen enum Constants {
        static let key = "APIKEY"
    }

    private init() {}
    
    // Direct implementation to send image to OpenAI Vision API
    public func analyzeImage(imageData: Data?, prompt: String = "Describe this image") async throws -> String {
        guard let imageData = imageData else {
            throw NSError(domain: "APICallerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image data provided"])
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(Constants.key)", forHTTPHeaderField: "Authorization")
        
        let base64Image = imageData.base64EncodedString()
        
        // Updated to use gpt-4o instead of the deprecated gpt-4-vision-preview
        let requestBody: [String: Any] = [
            "model": "gpt-4o",  // Updated to use the latest model with vision capabilities
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 300
        ]
        
        print("Sending image for analysis...")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print response status for debugging
        if let httpResponse = response as? HTTPURLResponse {
            print("Response status code: \(httpResponse.statusCode)")
        }
        
        // Print raw response data (full response for debugging)
        if let responseString = String(data: data, encoding: .utf8) {
            print("Raw response: \(responseString)")
        }
        
        // Parse the response - updated to handle the current response format
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            // Handle error response
            if let error = json?["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: "OpenAIError", code: 3,
                             userInfo: [NSLocalizedDescriptionKey: message])
            }
            
            // Parse successful response
            if let choices = json?["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            } else if let choices = json?["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let message = firstChoice["message"] as? [String: Any],
                    let contentArray = message["content"] as? [[String: Any]],
                    let firstContent = contentArray.first,
                    let text = firstContent["text"] as? String {
                // Alternative response format
                return text
            }
            
            throw NSError(domain: "APIResponseError", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        } catch {
            print("JSON parsing error: \(error)")
            throw error
        }
    }
}

// Define ImageSource for picking method
enum ImageSource {
    case photoLibrary
    case camera
}

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var responseText = "Select an image to analyze"
    @State private var isLoading = false
    @State private var showingImagePicker = false
    @State private var showingCameraPicker = false
    @State private var imageSource: ImageSource = .photoLibrary
    @State private var prompt = "Describe what you see in this image"
    @State private var debugInfo = ""
    @State private var showingCameraAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                        .padding(.horizontal)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 200)
                        .cornerRadius(12)
                        .overlay(
                            Text("No image selected")
                                .foregroundColor(.secondary)
                        )
                        .padding(.horizontal)
                }
                
                TextField("Enter analysis prompt", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                // Image Source buttons
                HStack(spacing: 15) {
                    Button(action: {
                        imageSource = .photoLibrary
                        showingImagePicker = true
                    }) {
                        VStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                            Text("Gallery")
                                .font(.caption)
                        }
                        .frame(minWidth: 80)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        imageSource = .camera
                        checkCameraPermission()
                    }) {
                        VStack {
                            Image(systemName: "camera")
                                .font(.system(size: 24))
                            Text("Camera")
                                .font(.caption)
                        }
                        .frame(minWidth: 80)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        Task {
                            await analyzeImage()
                        }
                    }) {
                        VStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 24))
                            Text("Analyze")
                                .font(.caption)
                        }
                        .frame(minWidth: 80)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || selectedImage == nil)
                }
                .padding(.horizontal)
                
                if isLoading {
                    ProgressView("Processing image...")
                        .padding()
                }
                
                VStack(alignment: .leading) {
                    Text("Analysis Result:")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Text(responseText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                
                // Debugging information
                if !debugInfo.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Debug Info:")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Text(debugInfo)
                            .font(.caption)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage, sourceType: .photoLibrary)
        }
        .sheet(isPresented: $showingCameraPicker) {
            ImagePicker(selectedImage: $selectedImage, sourceType: .camera)
        }
        .alert("Camera Access", isPresented: $showingCameraAlert) {
            Button("Settings", action: openSettings)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please allow camera access in Settings to use this feature.")
        }
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingCameraPicker = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        showingCameraPicker = true
                    }
                }
            }
        case .denied, .restricted:
            showingCameraAlert = true
        @unknown default:
            debugInfo = "Unknown camera permission status"
        }
    }
    
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    func analyzeImage() async {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.7) else {
            responseText = "No valid image to analyze"
            return
        }
        
        isLoading = true
        responseText = "Analyzing image..."
        debugInfo = ""
        
        do {
            let response = try await APICaller.shared.analyzeImage(imageData: imageData, prompt: prompt)
            await MainActor.run {
                responseText = response
                isLoading = false
            }
        } catch {
            print("Error occurred: \(error)")
            await MainActor.run {
                responseText = "Error: \(error.localizedDescription)"
                isLoading = false
                debugInfo = "Full error: \(error)"
            }
        }
    }
}

// Updated Image picker to handle both camera and photo library
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    var sourceType: UIImagePickerController.SourceType
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = true // Optional: allows cropping/editing the photo
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Use the edited image if available, otherwise use the original
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Add this to Info.plist:
// <key>NSCameraUsageDescription</key>
// <string>This app needs camera access to take photos for AI analysis</string>

#Preview {
    ContentView()
}
