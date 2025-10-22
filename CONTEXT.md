# Pulse Project

This document outlines the high-level architecture, data flow, and key components of the Pulse project. It serves as a central reference for how the hardware, firmware, and software interact.

## System Architecture

The system follows a **data streaming architecture**. A low-power wearable device is responsible for raw data acquisition, while a companion iOS application handles all the intensive computation and user-facing logic.

The main components are:
1.  **Wearable Device**: A custom-designed PCB with sensors and firmware. Its only job is to collect and transmit data.
2.  **iOS Companion App**: A Swift application that connects to the wearable, processes the raw data, runs the machine learning model, and displays the results.

---

## Workflow & Data Flow

The end-to-end process for detecting sleep is as follows:

1.  **Data Acquisition (Wearable)**: The firmware on the wearable's microcontroller continuously reads raw data from the heart rate sensor and the accelerometer.
2.  **Data Transmission (BLE)**: The raw sensor readings are packaged and transmitted over a Bluetooth Low Energy (BLE) connection.
3.  **Data Reception (iOS App)**: The app's `BLEManager` class establishes a connection with the wearable and subscribes to the data characteristic, receiving a stream of raw data packets.
4.  **Feature Engineering (iOS App)**: The raw data is passed to a `DataProcessor` module. This module **re-implements the logic from the Python `preprocess.py` script in Swift**. It calculates the rolling statistics (e.g., mean and standard deviation over 5 and 15-minute windows) and other features to create a feature vector.
5.  **Inference (iOS App)**: The engineered feature vector is fed into the **Core ML model**.
6.  **Display (iOS App)**: The model returns a prediction (e.g., 0 for "AWAKE", 1 for "SLEEPING"). The SwiftUI user interface updates to display the current sleep state to the user.

---

## Component Breakdown

### 1. Wearable Device Hardware

The wearable device is a custom-designed Printed Circuit Board (PCB) engineered for minimal size and low power consumption, making it suitable for continuous wear.

* **Design Philosophy**: The hardware design prioritizes a compact form factor and energy efficiency. Component selection was driven by the need for reliable data acquisition and efficient wireless transmission over Bluetooth Low Energy (BLE).

* **Core Components**:
    * **Microcontroller (MCU)**: An **ESP32-WROOM-32E (U1)** serves as the main processor. It was selected for its dual-core architecture, integrated Wi-Fi and BLE capabilities, and extensive low-power modes, which are critical for managing battery life.
    * **Accelerometer & Magnetometer**: An **FXOS8700CQR1 (U8)** is used for motion tracking. This 6-axis sensor provides the raw accelerometer data needed to detect movement and activity levels.
    * **Heart Rate Sensor**: The board integrates a dedicated heart rate sensor IC (**U3**) to capture cardiovascular data.
    * **Power Management**: The power subsystem is managed by dedicated ICs (**U4**, **U5**) that regulate voltage and handle battery charging via a **USB-C connector (U7)**. This ensures stable power delivery to all components.

    ![SCH_Schematic](https://i.imgur.com/c2dHO15.png$0)

* **Connectivity**:
    * **Primary (Data)**: Bluetooth Low Energy (BLE) for streaming sensor data to the companion iOS application.
    * **Secondary (Service)**: 
      * A USB-C port provides the physical interface for battery charging and initial firmware programming.
      * A 3-pin header (H1) is also included on the board, exposing GND, TX, and RX pins for low-level hardware debugging.

    ![3D_render_PCB](https://i.imgur.com/XnQge40.png$0)

* **PCB Layout & Component Placement Strategy**: The PCB utilizes a two-sided component placement strategy to optimize for size, sensor performance, and signal integrity.

    * **Top Side**: As shown in the 2D render, this side houses the main digital and power components. This includes the ESP32 MCU (**U1**), the accelerometer (**U8**), power management ICs (**U4, U5**), and the USB-C connector (**U7**). Placing these components together contains digital noise and simplifies the routing of power and high-speed signals.

    <p align="center">
        <img src="https://i.imgur.com/bLLGVY8.png$0" alt="2D_render" width="500"/>
    </p>

    * **Bottom (Skin-Facing) Side**: This side is dedicated to sensors that require direct proximity or contact with the user's skin. It contains the heart rate sensor (**U3**) and the sensor **U9**. This physical separation isolates the sensitive analog sensors from the noisy digital logic on the top side, ensuring cleaner and more reliable data acquisition.

    <p align="center">
        <img src="https://i.imgur.com/wSPXkMZ.png$0" alt="2D_render" width="500"/>
    </p>

* **Status**: Design complete, awaiting fabrication and assembly.

* **Firmware**: The embedded software responsible for initializing sensors, managing power, and handling BLE communication. It does **not** perform any feature calculation.

### 2. iOS Companion App
* **BLE Manager**: A Swift class that handles scanning, connecting, and receiving data from the wearable.
* **Data Processor**: Swift code that transforms the incoming raw data stream into the feature vectors required by the model.
* **Core ML Model**: The final, tuned XGBoost model, converted from `.joblib` to the `.mlmodel` format using `coremltools`. This allows for efficient on-device inference.
* **SwiftUI View**: The user interface that displays connection status and the final sleep prediction.

---

## Sleep Detection Algorithm

The core of the sleep detection logic is a supervised machine learning model. It was trained to recognize the subtle patterns in physiological data that distinguish sleep from wakefulness. The model does not make decisions on raw sensor data directly; instead, it uses a set of carefully crafted features that summarize the user's state over time.

### 1. Key Features

The model's performance relies on **feature engineering**, where raw data is transformed into meaningful inputs. The most important features include:

* **Windowed Statistics**: Basic statistics like the mean and standard deviation of heart rate and the "Vector Magnitude" (overall movement) calculated over 60-second intervals.
* **Rolling Statistics (Temporal Context)**: This is the most critical feature set. The model considers the **mean and standard deviation of heart rate and movement over longer, overlapping windows (5 and 15 minutes)**. These features give the model a sense of trend and context. For example, it can learn that a sustained period of low movement and a gradually decreasing heart rate is a strong indicator of falling asleep.

### 2. The Model: Tuned XGBoost

After comparing several algorithms (including Logistic Regression and Random Forest), a **Tuned XGBoost (Extreme Gradient Boosting) Classifier** was selected as the final model.

```
              precision    recall  f1-score   support

   False           0.99      0.93      0.96      4893
    True           0.76      0.95      0.85      1182

accuracy                               0.93      6075

macro avg          0.87      0.94      0.90      6075
weighted avg       0.94      0.93      0.94      6075
```

* **Why XGBoost?** XGBoost is a powerful and efficient tree-based algorithm known for its high performance in classification tasks. It builds a series of decision trees, where each new tree corrects the errors of the previous one, resulting in a highly accurate predictive model.
* **Tuning**: The model's hyperparameters were optimized using `RandomizedSearchCV` to find the best settings for this specific problem, maximizing its F1-score.

### 3. Training & Output

* **Training Data**: The model was trained and validated on the public **MMASH (Multilevel Monitoring of Activity and Sleep in Healthy People) dataset**.
* **Final Output**: For each 60-second window of incoming sensor data, the algorithm processes the features and outputs a single prediction: `0` (AWAKE) or `1` (SLEEPING).

---

## Key Decisions & Open Questions

* **BLE Data Protocol (Undecided)**: The exact format for transmitting data from the wearable to the app has not been finalized. The goal is to choose a simple and efficient format.
    * **Option A (CSV String)**: Simple to parse (e.g., `"72.5,1.05,0"`). Human-readable for debugging.
    * **Option B (Raw Bytes)**: Most efficient in terms of size, but requires careful byte-level parsing on the app side.
* **Model Porting**: The feature engineering pipeline written in Python/pandas **must be perfectly replicated in Swift**. Any discrepancy in the calculation of rolling statistics will lead to poor model performance.
