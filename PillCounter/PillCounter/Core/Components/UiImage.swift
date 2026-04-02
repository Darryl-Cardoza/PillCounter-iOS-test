//
//  UiImage.swift
//  PillCounter
//
//  Created by Bhushan Patil on 10/03/26.
//
import SwiftUI

extension UIImage {

    func normalized() -> UIImage {

        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))

        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? self
    }
}
