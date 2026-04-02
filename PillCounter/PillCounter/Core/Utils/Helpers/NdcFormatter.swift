//
//  NdcFormatter.swift
//  PillCounter
//
//  Created by Bhushan Patil on 20/03/26.
//

func formatNDC(_ value: String) -> String {
    
    // remove everything except digits
    let digits = value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    
    let part1 = digits.prefix(5)
    let part2 = digits.dropFirst(5).prefix(3)
    let part3 = digits.dropFirst(8).prefix(2)
    
    var result = String(part1)
    
    if !part2.isEmpty {
        result += "-" + part2
    }
    
    if !part3.isEmpty {
        result += "-" + part3
    }
    
    return result
}
