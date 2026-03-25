# 💊 Pill Counter

<p align="center">
  A smart iOS application to accurately count pills using an offline machine learning model.
</p>

## 📑 Table of Contents
- [✨ What's Included](#-whats-included)
- [🛠️ Tech Stack](#️-tech-stack)
- [📋 Prerequisites](#-prerequisites)
- [🚀 Project Setup (Step by Step)](#-project-setup-step-by-step)
- [🏃 Running the Project](#-running-the-project)
- [🧪 Testing](#-testing)
- [📁 Folder Structure Overview](#-folder-structure-overview)
- [⚙️ Configuration Details](#️-configuration-details)
- [📦 Adding a New Module](#-adding-a-new-module)

---

## ✨ What's Included
* **Offline Pill Counting**: CoreML-based object detection for precise pill counting without an internet connection.
* **Localization**: Built-in support for multiple languages (English, Spanish, French, Hindi).
* **Secure Environment**: Data encryption and security violation protections.
* **Modern UI**: Fully built with SwiftUI for a seamless, declarative user experience.
* **CoreData Integration**: Local storage capabilities to save previous count records.

---

## 🛠️ Tech Stack
* **Language:** Swift 5+
* **Framework:** SwiftUI
* **Machine Learning:** CoreML & Vision Framework
* **Local Storage:** CoreData
* **Architecture:** MVVM (Model-View-ViewModel) + Feature Modules

---

## 📋 Prerequisites
Before you begin, ensure you have met the following requirements:
* **Operating System:** macOS (for Xcode)
* **IDE:** Xcode 15.0 or later
* **iOS Target:** iOS 16.0+

---

## 🚀 Project Setup (Step by Step)
1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd mobrite_pill_counter_ios
   ```
2. **Open the project in Xcode:**
   Navigate into the project directory and open the `.xcodeproj` file.
   ```bash
   cd PillCounter
   open PillCounter.xcodeproj
   ```
3. **Resolve Dependencies:**
   If using Swift Package Manager (SPM), wait for Xcode to automatically resolve all packages.

---

## 🏃 Running the Project
1. Select the **PillCounter** scheme at the top of Xcode.
2. Choose a destination: select your connected iOS device (recommended for camera access and ML features) or an iOS Simulator.
3. Press `Cmd + R` or click the **Run** (Play) button in the upper left corner to build and run the application.

---

## 🧪 Testing
The project includes both Unit and UI tests.
1. Make sure the scheme is set to **PillCounter**.
2. Press `Cmd + U` or go to **Product > Test** from the top menu to run the test suite.
3. Test targets include:
   * `PillCounterTests` for logic and Unit testing.
   * `PillCounterUITests` for automated interface testing.

---

## 📁 Folder Structure Overview
Here is a high-level overview of our project structure:

```
PillCounter/
├── Assets.xcassets/        # App icons, colors, and static image assets
├── Base/                   # Foundational classes and extensions
├── Core/                   # Core functions like Network/ML models
├── Features/               # Main application features and views
├── Navigation/             # Navigation and routing logics
├── Preview Content/        # Mock data for SwiftUI previews
├── PillCounter.xcdatamodeld/ # CoreData database scheme
└── PillCounterApp.swift    # Application entry point
```

---

## ⚙️ Configuration Details
* **App Entitlements:** Required capabilities are specified in `PillCounter.entitlements`.
* **Config Files:** Sensitive configurations may be utilizing encrypted properties (e.g., `Config.plist.enc`).
* **Info.plist:** Contains essential app configuration details such as Camera permission strings which are crucial for the ML model to operate.

---

## 📦 Adding a New Module
To add a new feature module:
1. Navigate to the `Features` folder.
2. Create a new folder for your feature (e.g., `HistoryLog`).
3. Add the necessary files following the MVVM pattern:
   * `HistoryLogView.swift` (UI)
   * `HistoryLogViewModel.swift` (Logic)
   * `HistoryLogModel.swift` (Data)
4. Update the `Navigation` logic to map and route to the newly created view.
