//
//  LocationService.swift
//  PillCounter
//
//  Created by Bhushan Patil on 14/04/26.
//

import CoreLocation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationService()

    private let manager = CLLocationManager()

    @Published var locationString: String = "Fetching..."

    private override init() {
        super.init()
        manager.delegate = self
    }

    // Ask permission
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    // Start fetching location
    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self = self else { return }

            if let place = placemarks?.first {

                let area = place.subLocality ?? ""
                let city = place.locality ?? place.administrativeArea ?? ""
                let pincode = place.postalCode ?? ""

                // Format: Andheri, Mumbai - 400053
                self.locationString = [
                    [area, city].filter { !$0.isEmpty }.joined(separator: ", "),
                    pincode.isEmpty ? nil : pincode
                ]
                .compactMap { $0 }
                .joined(separator: " - ")

            } else {
                self.locationString = "Location unavailable"
            }
        }

        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationString = "Location unavailable"
    }
}
