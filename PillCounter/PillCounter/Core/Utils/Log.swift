//
//  Log.swift
//  PillCounter
//
//  Created by Bhushan Patil on 16/04/26.
//
import Foundation



public func Log(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    #if DEBUG
    let fileName = (file as NSString).lastPathComponent
    print("[\(fileName):\(line)] \(function) → \(message)")
    #endif
}
