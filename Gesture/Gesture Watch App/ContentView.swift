//
//  ContentView.swift
//  Gesture Watch App
//
//  Created by Abhinav Pottabathula on 4/8/23.
//

import SwiftUI
import WatchConnectivity
import WatchKit
import CoreMotion
import HealthKit


class SessionDelegate: NSObject, WCSessionDelegate, ObservableObject {
    
    // Handle session delegate methods
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Activation failed with error: \(error.localizedDescription)")
            return
        }
        
        if activationState == .activated {
            print("Session activated!")
        }
    }
    
    func session(_ session: WCSession, didBecomeInactiveWithError error: Error?) {
        if let error = error {
            print("Session became inactive with error: \(error.localizedDescription)")
        } else {
            print("Session became inactive")
        }
    }
    
    func session(_ session: WCSession, didDeactivateWith error: Error?) {
        if let error = error {
            print("Session deactivated with error: \(error.localizedDescription)")
        } else {
            print("Session deactivated")
            session.activate()
        }
    }
}



struct ContentView: View {

    // Set up WatchConnectivity session and delegate
    @State private var session: WCSession?
    @State var sessionDelegate = SessionDelegate()
    
    // Set up CoreMotion manager to capture motion data
    let motion = CMMotionManager()
    
    // Set up timer to send motion data to iOS app periodically
    @State var timer: Timer?
    @State private var isTimerRunning = false
    @State private var timeElapsed = 0.0
    
    @State var isRecording = false
    
    var body: some View {
        VStack {
            Button(action: {
                toggleRecording()
            }) {
                Text(self.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline)
                    .padding()
                    .foregroundColor(.white)
                    .background(self.isRecording ? Color.red : Color.blue)
                    .cornerRadius(10)
            }
            .padding()
        }
        .onAppear {
            // Check if the Watch app is reachable
            if WCSession.isSupported() {
                session = WCSession.default
                session?.delegate = sessionDelegate
                session?.activate()
            }
        }
    }
    
        
    // Health workout session
    let healthStore = HKHealthStore()

    // The quantity type to write to the health store.
    let typesToShare: Set = [
        HKQuantityType.workoutType()
    ]

    // The quantity types to read from the health store.
    let typesToRead: Set = [
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
    ]

    let configuration = HKWorkoutConfiguration()
    
//    @State var workoutSession = HKWorkoutSession(configuration: HKWorkoutConfiguration())
//    @State var builder: HKLiveWorkoutBuilder
    
    @State var workoutSession: HKWorkoutSession = {
        do {
            let config = HKWorkoutConfiguration()
            let healthStore = HKHealthStore()
            config.activityType = .running
            config.locationType = .outdoor
            
            return try HKWorkoutSession(healthStore: healthStore, configuration: config)
        } catch {
            print(error)
            fatalError("Couldn't create workout session.")
        }
    }()
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
        isRecording.toggle()
    }

    private func stopRecording() {
        timer?.invalidate()
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
    }

    func startRecording() {
        // Update interval for recording motion data
        let updateInterval = 1.0 / 15.0 // 60 Hz
        
        motion.deviceMotionUpdateInterval = updateInterval
        motion.startDeviceMotionUpdates()

        motion.accelerometerUpdateInterval = updateInterval
        motion.startAccelerometerUpdates()
        
        do {
            configuration.activityType = .running
            configuration.locationType = .outdoor

//            // Request authorization for those quantity types.
//            healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
//                // Handle errors here.
//                if let error = error {
//                    print("health store failed with error: \(error.localizedDescription)")
//                }
//            }
//
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = workoutSession.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                         workoutConfiguration: configuration)

            workoutSession.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { (success, error) in

//                guard success else {
//                    // Handle errors.
//                    print("Error failed to begin workout collection: \(String(describing: error?.localizedDescription))")
//                }

                // Indicate that the session has started.
                print("session started")
            }

        } catch {
            print("Couldn't start workout session.")
        }



        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            var xAccel = 0.0
            var yAccel = 0.0
            var zAccel = 0.0
            var xRot = 0.0
            var yRot = 0.0
            var zRot = 0.0
            
            if let acceleration = motion.accelerometerData?.acceleration {
                xAccel = acceleration.x
                yAccel = acceleration.y
                zAccel = acceleration.z
            }
            
            if let rotationRate = motion.deviceMotion?.rotationRate {
                xRot = rotationRate.x
                yRot = rotationRate.y
                zRot = rotationRate.z
            }
            
            let motionData = [xAccel, yAccel, zAccel, xRot, yRot, zRot]

            let timestamp = String(Date().timeIntervalSince1970)
            let motionDataRow = "\(timestamp),\(xAccel),\(yAccel),\(zAccel),\(xRot),\(yRot),\(zRot)"

            let message = ["motionData": motionData, "motionDataRow": motionDataRow]
            if let session = session, session.isReachable {
                session.sendMessage(message, replyHandler: nil, errorHandler: { error in
                    print("Error sending motion data: \(error.localizedDescription)")
                })
            } else {
                print("Session not reachable")
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
