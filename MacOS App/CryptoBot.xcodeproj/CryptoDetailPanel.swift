//
//  File.swift
//  
//
//  Created by Developer on 2023-07-20.
//

import Foundation

class SomeClass {

    func exampleMethod() {
        print("Start")
        // Some logic here
        let result = 2 + 2
        print("Result is \(result)")
    }

    func anotherMethod() {
        // Some non-throwing code
        print("Processing started")
        let values = [1, 2, 3]
        for value in values {
            print("Value: \(value)")
        }
        print("Processing ended")
    }
    
    func methodWithDoCatch() {
        // Removed do/catch as no throwing calls inside
        print("Inside methodWithDoCatch")
        let sum = 10 + 20
        print("Sum is \(sum)")
    }
    
    func methodWithThrowingCall() {
        do {
            try throwingFunction()
        } catch {
            print("Caught error: \(error)")
        }
    }
    
    func throwingFunction() throws {
        // Just an example throwing function
        throw NSError(domain: "ExampleError", code: 1, userInfo: nil)
    }
}
