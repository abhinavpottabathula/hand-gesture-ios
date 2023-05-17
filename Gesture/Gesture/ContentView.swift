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
import ClientRuntime
import AWSClientRuntime
import AWSS3


public class S3manager : ObservableObject {
    private var client: S3Client?
    public var files: [String]?
    private let s3BucketName = "gesture-recordings"
    private let s3ObjectKey = "sensor_data"

    
    init() {
        Task(priority: .high) {
            do {
                setenv("AWS_ACCESS_KEY_ID", "", 1)
                setenv("AWS_SECRET_ACCESS_KEY", "", 1)
                
                client = try S3Client(region: "us-west-1")
                files = try await listBucketFiles(bucket: "bucket_name")
            } catch {
                print("hit init error")
                print(error)
            }
        }
    }
    
    public func createFile(withData data: String) {
        Task(priority: .high) {
            do {
                let dataStream = ByteStream.from(stringValue: data)

                let input = PutObjectInput(
                    body: dataStream,
                    bucket: self.s3BucketName,
                    key: String(Date().timeIntervalSince1970) + "_" + self.s3ObjectKey + ".csv"
                )
                _ = try await client?.putObject(input: input)

            } catch {
                print("Failed to upload s3 file: \(error)")
            }
        }
    }
    
    // from https://docs.aws.amazon.com/sdk-for-swift/latest/developer-guide/examples-s3-objects.html
    public func listBucketFiles(bucket: String) async throws -> [String] {
        
        if let clientInstance = client {
            let input = ListObjectsV2Input(
                bucket: bucket
            )
            let output = try await clientInstance.listObjectsV2(input: input)
            var names: [String] = []
            
            guard let objList = output.contents else {
                return []
            }
            
            for obj in objList {
                if let objName = obj.key {
                    names.append(objName)
                }
            }
            
            return names
            
        } else {
            print("Client has not been initialized!")
            return [String]()
        }
    }
}


class WatchSessionDelegate: NSObject, WCSessionDelegate {
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("sessionDidBecomeInactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
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
//        print("Recieved message")
//        print(message)
//        if let data = message["motionDataRow"] as? String {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("MotionDataReceived"), object: message)
        }
    }
}

struct ContentView: View {
    @State private var motionDataText: String = "No data received yet"
    let watchSessionDelegate = WatchSessionDelegate()
    
    // Setup AWS S3 manager
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    @StateObject private var s3Client = S3manager()
    
    private let csvFileName = "sensorData.csv"
    private let csvHeader = "timestamp,xAccel,yAccel,zAccel,xRot,yRot,zRot,gesture\n"
    @State var csvText = "timestamp,xAccel,yAccel,zAccel,xRot,yRot,zRot,gesture\n"
    
    @State private var selectedOption = "Clench"
    let options = ["Clench", "Double Clench", "Pinch", "Double Pinch"]
    
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
    @State private var classificationText: String = "No classification yet"
    @State private var classificationProb: Double = 0.0
    
    let synth = AVSpeechSynthesizer()
        
    private func readOut(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synth.speak(utterance)
    }
    
    var body: some View {
        VStack {
            Button(action: {
                csvText = csvHeader
            }) {
                Text("Clear Data")
            }
            Button(action: {
                s3Client.createFile(withData: csvText)
                csvText = csvHeader
            }) {
                Text("Save to S3")
                    .padding()
            }
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
                    Label("Select Gesture", systemImage: "chevron.down.circle")
                        .font(.headline)
                }
                Text("Selected Gesture: \(selectedOption)")
            }
            Text(classificationText + ": " + String(classificationProb))
                .padding()
            Text(motionDataText)
                .padding()
                .onAppear {
                    do{
                        try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
                        try AVAudioSession.sharedInstance().setActive(true)
                     }
                    catch
                    { print("Fail to enable session") }
                    
                    if WCSession.isSupported() {
                        let session = WCSession.default
                        session.delegate = watchSessionDelegate
                        session.activate()
                    }
                    
                    NotificationCenter.default.addObserver(forName: Notification.Name("MotionDataReceived"), object: nil, queue: nil) { notification in
                        if let data = notification.object as? Dictionary<String, Any> {
                            let motionDataTxt = data["motionDataRow"] as! String + "," + selectedOption + "\n"
                            self.csvText.append(motionDataTxt)
                            
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
                                
                                var prevClassText = classificationText
                                
                                if pred.classProbability[0]! > pred.classProbability[1]! {
                                    classificationText = "Clench"
                                    classificationProb = pred.classProbability[0]!
                                } else {
                                    classificationText = "Pinch"
                                    classificationProb = pred.classProbability[1]!
                                }
                                
                                if prevClassText != classificationText {
                                    readOut(text: classificationText)
                                }
                            }
                        }
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
