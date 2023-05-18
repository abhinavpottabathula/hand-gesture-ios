//
//  OpenAIManager.swift
//  Gesture
//
//  Created by Abhinav Pottabathula on 5/17/23.
//

import Foundation
import OpenAI


public class OpenAIManager : ObservableObject {
    private var openAIClient: OpenAI
    let prompt = """
        You are a helpful assistant.

        You will be given a bunch of lists that include words and probability. Your job is to select one word from each list to construct a grammatically correct and meaningful sentence. You can only pick 1 word from each list.
    
        {Apple(70%), tired (30%)}
        {is (60%),crazy(30%),beautiful(10%)}
        {favorite(50%),jump(20%),sit(30%)}
        {my(50%),sandwich(20%),maximum(30%)}
        {fruit(50%),or(20%),but(30%)}
    """
    public var sentenceResponse: String

    
    init() {
        openAIClient = OpenAI(apiToken: "")
        sentenceResponse = "no response"
    }
    
    public func getSentence() {
        Task(priority: .high) {
            do {
                let query = ChatQuery(model: .gpt3_5Turbo, messages: [.init(role: .user, content: prompt)], temperature: 0.1, maxTokens: 256)
                var chatResult = try await openAIClient.chats(query: query)

                sentenceResponse = chatResult.choices[0].message.content
            } catch {
                print("OpenAI Error: \(error)")
            }
        }
    }
}
