//
//  ContentView.swift
//  Gesture
//
//  Created by Abhinav Pottabathula on 4/8/23.
//

import SwiftUI
import CoreMotion
import CoreML
import WatchConnectivity
import AVFoundation

import Foundation


class WatchSessionDelegate: NSObject, WCSessionDelegate {
    func sessionDidBecomeInactive(_ session: WCSession) {
        session.activate()
        print("sessionDidBecomeInactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        print("sessionDidDeactivate")
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        switch activationState {
        case .activated:
            print("WCSession activated successfully")
        case .inactive:
            print("Unable to activate the WCSession. Error: \(error?.localizedDescription ?? "--")")
        case .notActivated:
            print("Unexpected .notActivated state received after trying to activate the WCSession")
        @unknown default:
            print("Unexpected state received after trying to activate the WCSession")
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("MotionDataReceived"), object: message)
        }
    }
}

struct ContentView: View {
    @State private var motionDataText: String = ""
    let watchSessionDelegate = WatchSessionDelegate()
    
    // Setup AWS S3 manager
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    @StateObject private var s3Client = S3manager()
    
    private let csvFileName = "sensorData.csv"
    private let csvHeader = "timestamp,xAccel,yAccel,zAccel,xRot,yRot,zRot,gesture\n"
    @State var csvText = "timestamp,xAccel,yAccel,zAccel,xRot,yRot,zRot,gesture\n"
    
    // Model setup
    let model: SVM = {
        do {
            let config = MLModelConfiguration()
            return try SVM(configuration: config)
        } catch {
            print(error)
            fatalError("Couldn't create SVM model.")
        }
    }()
    @State var motionDataBuffer: [[Double]] = []
    @State private var classificationText: String = "Start Recording!"
    @State private var classificationProb: Double = 0.0
    
    // Classification Buffer of last seen words to pass to LLM for sentence prediction
    @State var wordsBuffer: [Dictionary<String, Double>] = []
    
    // OpenAI LLM
    @StateObject private var openAIClient = OpenAIManager()
    @State var sentence = "OpenAI response..."
    
    let classifierMap: [Int64: String] = [
        0: "hello",
        1: "empower",
        2: "connect",
        3: "world",
        4: "silence",
        5: "clench",
    ]

    @State private var selectedOption = "hello"
    let options = ["hello", "world", "connect", "empower", "silence"]
    

    // Text to Speech Synthesizer
    let synth = AVSpeechSynthesizer()
    private func readOut(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synth.speak(utterance)
    }
    

    private func classifyData(data: Dictionary<String, Any>) {
        if motionDataBuffer.count < 10 {
            motionDataBuffer.append(data["motionData"] as! [Double])
        } else {
            // Predict on rolling average of the last data 10 points
            motionDataBuffer.removeFirst()
            motionDataBuffer.append(data["motionData"] as! [Double])

            // Take the average of motionDataBuffer columnwise.
            var columnAverages: [Double] = Array(repeating: 0.0, count: 6)
            for row in motionDataBuffer {
                for (index, value) in row.enumerated() {
                    columnAverages[index] += value
                }
            }
            columnAverages = columnAverages.map { $0 / Double(motionDataBuffer.count) }


            guard let mlMultiArray = try? MLMultiArray(shape:[6], dataType:MLMultiArrayDataType.double) else {
                fatalError("Unexpected runtime error. MLMultiArray")
            }
            for (index, element) in columnAverages.enumerated() {
                mlMultiArray[index] = NSNumber(floatLiteral: element)
            }

            let modelInput = SVMInput(input: mlMultiArray)
            guard let pred = try? model.prediction(input: modelInput) else {
                fatalError("Unexpected runtime error.")
            }
            
            // Only update UI if we have a high classification accuracy
            if pred.classProbability[pred.classLabel]! > 0.8 {
                let prevClassText = classificationText
                
                classificationText = classifierMap[pred.classLabel]!
                classificationProb = pred.classProbability[pred.classLabel]!

                if prevClassText != classificationText {
                    var wordProbs: [String: Double] = [:]
                    for (intKey, prob) in pred.classProbability {
                        wordProbs[classifierMap[intKey]!] = prob
                    }
                    
                    wordsBuffer.append(wordProbs)
                    readOut(text: classificationText)
                }
            }
        }
    }
    
    var body: some View {
        VStack {
            Text(classificationText)
                .font(.system(size: 40, weight: .bold))
            Text("Accuracy: " + String(classificationProb))
            Image(classificationText)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200) // Adjust the size according to your needs
            Text(motionDataText)
                .padding()
                .onAppear {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
                        try AVAudioSession.sharedInstance().setActive(true)
                     } catch {
                         print("Fail to enable session")
                     }
                    
                    if WCSession.isSupported() {
                        let session = WCSession.default
                        session.delegate = watchSessionDelegate
                        session.activate()
                    }
                    
                    NotificationCenter.default.addObserver(forName: Notification.Name("MotionDataReceived"), object: nil, queue: nil) { notification in
                        if let data = notification.object as? Dictionary<String, Any> {
                            // Write data to text string for S3 upload
                            let motionDataTxt = data["motionDataRow"] as! String + "," + selectedOption + "\n"
                            csvText.append(motionDataTxt)
                            
                            classifyData(data: data)
                            
                            print("DICTIONARIES: ")
                            print(wordsBuffer.suffix(5))
                            
                            // Generate a new sentence including the latest words and read it
                            // out loud if it is a new sentence.
                            var prevSentence = sentence
                            openAIClient.getSentence(wordProbs: wordsBuffer.suffix(5))
                            sentence = openAIClient.sentenceResponse
                            if sentence != prevSentence {
                                readOut(text: sentence)
                            }
                        }
                    }
                }
            
            Text(sentence)
                .padding()
            VStack {
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button(action: {
                            self.selectedOption = option
                        }) {
                            Text(option)
                        }
                    }
                } label: {
                    Label("Select Gesture to Save", systemImage: "chevron.down.circle")
                        .font(.headline)
                }
                Text(selectedOption)
                    .padding()
            }
            
            HStack {
                Button(action: {
                    csvText = csvHeader
                }) {
                    Image(systemName: "trash")
                        .font(Font.system(size: 30))
                        .padding()
                }
                Button(action: {
                    s3Client.createFile(withData: csvText)
                    csvText = csvHeader
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(Font.system(size: 30))
                        .padding()
                }
            }
        }
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
