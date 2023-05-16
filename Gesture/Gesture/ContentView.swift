//
//  ContentView.swift
//  Gesture
//
//  Created by Abhinav Pottabathula on 4/8/23.
//

import SwiftUI
import CoreMotion
import WatchConnectivity

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
        print("Recieved message")
        print(message)
        if let data = message["motionData"] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("MotionDataReceived"), object: data)
            }
        }
    }
}

struct ContentView: View {
    @State private var motionData: String = "No data received yet"
    let watchSessionDelegate = WatchSessionDelegate()
    
    // Setup AWS S3 manager
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    @StateObject private var s3Client = S3manager()
    
    private let csvFileName = "sensorData.csv"
    private let csvHeader = "timestamp,xAccel,yAccel,zAccel,xRot,yRot,zRot,gesture\n"
    @State var csvText = "timestamp,xAccel,yAccel,zAccel,xRot,yRot,zRot,gesture\n"
    
    @State private var selectedOption = "clench"
    let options = ["Clench", "Double Clench", "Pinch", "Double Pinch"]

    
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
            }
            VStack {
                Text("Selected Gesture: \(selectedOption)")
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
            }
            Text(motionData)
                .padding()
                .onAppear {
                    if WCSession.isSupported() {
                        let session = WCSession.default
                        session.delegate = watchSessionDelegate
                        session.activate()
                    }
                    
                    NotificationCenter.default.addObserver(forName: Notification.Name("MotionDataReceived"), object: nil, queue: nil) { notification in
                        if let data = notification.object as? String {
                            motionData = data + "," + selectedOption + "\n"
                            self.csvText.append(motionData)
                            print(motionData)
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
