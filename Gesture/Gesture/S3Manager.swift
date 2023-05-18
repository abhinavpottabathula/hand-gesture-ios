//
//  S3Manager.swift
//  Gesture
//
//  Created by Abhinav Pottabathula on 5/17/23.
//

import Foundation

import AWSClientRuntime
import AWSS3
import ClientRuntime


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
