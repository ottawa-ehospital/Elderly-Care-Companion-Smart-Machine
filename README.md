# Elderly-Care-Companion-Smart-Machine

## Authors

- Lu, Yiting - 300479578
- Mousavi, Seyedehsan - 300459758

## Project Overview

This project is an elderly-care companion smart vehicle system with person following, fall detection, obstacle avoidance, live monitoring, fall event recording, medication reminders, and vital-sign management.

The system contains three main parts:

1. **Raspberry Pi vehicle-side software**  
   Runs on the smart vehicle. It handles camera processing, MediaPipe-based posture analysis, fall detection, person following, obstacle avoidance, gimbal control, chassis control, and vehicle-side HTTP APIs.

2. **Flask back-end service**  
   Runs on a connected device. It communicates with the Raspberry Pi, retrieves robot status and camera frames, manages fall event records and videos, stores user data, and provides APIs for the mobile app.

3. **Flutter mobile app**  
   Provides the user interface for login/register, live monitoring, robot control, fall event review, vital signal records, medication reminders, profile management, and local notifications.

---

## Raspberry Pi Vehicle-Side Software

The Raspberry Pi vehicle-side software has already been deployed on the Raspberry Pi attached to the vehicle. After the vehicle is powered on, the main vehicle-side programs start automatically.

The related code is stored in:

```Directory
Elderly-Care-Companion-Smart-Machine/smart_vehicle_raspberry_pi
```

This part is mainly provided for reference. To run the full vehicle-side system, the HiWonder TurboPi hardware platform and the official TurboPi SDK are required.

---

## Flask Back-End Service

The back-end code is stored in:

```Directory
Elderly-Care-Companion-Smart-Machine/smart_vehicle_backend
```

The back-end communicates with the Raspberry Pi vehicle-side API, manages fall event records and videos, stores user data, and provides APIs for the Flutter mobile app.

---

### Switching Between Direct Connection Mode and LAN Mode

Currently, the system is configured for **Direct Connection mode**.

In Direct Connection mode, after the vehicle is powered on, the Raspberry Pi creates a hotspot. The device running the mobile app should connect to this hotspot in order to control the vehicle and receive its status information.

To switch between Direct Connection mode and LAN mode, update the Raspberry Pi API address in the following files:

- smart_vehicle_backend/app_runtime.py
- smart_vehicle_backend/blueprints/live.py
- smart_vehicle_backend/services/robot_controller.py

Use the correct PI_BASE_URL according to the network mode:

LAN mode:
```code
PI_BASE_URL = "http://192.168.2.80:8000"
```

Direct Connection mode:
```code
PI_BASE_URL = "http://192.168.149.1:8000"
```

Make sure the selected IP address matches the actual IP address of the Raspberry Pi under the current network.

---

## How to Run the Back-End

Please run the following commands from the project root folder:

```directory
Elderly-Care-Companion-Smart-Machine
```

### 1. Install required libraries

For macOS or Linux:

```bash
bash install.sh
```

For Windows PowerShell:

```shell
.\install.ps1
```

This will create a virtual environment, install the required Python libraries for the back-end and Flutter dependencies for the mobile app.

---

### 2. Activate the virtual environment

For macOS or Linux:

```bash
cd smart_vehicle_backend
source .venv/bin/activate
```

For Windows PowerShell:

```shell
cd smart_vehicle_backend
.\.venv\Scripts\Activate.ps1
```

---

### 3. Run the back-end

After entering the virtual environment, run:

```terminal
python3 app.py
```

If python3 does not work on your device, use:

```terminal
python app.py
```

After the back-end starts successfully, it should run on:

http://127.0.0.1:5050

---

## HTML-Based Web Dashboard

We kept the original HTML-based web dashboard that was used for the mid-term presentation.

After the back-end is running, it can be opened in a local browser through:

http://127.0.0.1:5050

However, this dashboard is not the main front-end anymore. Since the front-end design was later changed to a Flutter mobile app, the HTML dashboard has not been fully updated and some functions may no longer work properly.

---

## Flutter Mobile App

The Flutter mobile app is the main user interface of the current system.

Before running the app, make sure the back-end is running and the app is configured with the correct back-end address.

The Flutter app code is stored in:

```Directory
Elderly-Care-Companion-Smart-Machine/smart_vehicle_app
```

### Run on macOS (Recommended)

```terminal
cd smart_vehicle_app
flutter run -d macos
```

### Run on Chrome

```terminal
cd smart_vehicle_app
flutter run -d chrome
```

### Run on a simulator

First, check the available devices:

```terminal
flutter devices
```

If an iOS simulator or Android emulator is already listed, run the app with the corresponding device ID:

```terminal
flutter run -d YOUR_DEVICE_ID
```

If no simulator or emulator is listed, check the available emulators:

```terminal
flutter emulators
```

Then run:
Then launch one emulator by replacing `YOUR_EMULATOR_ID` with the emulator ID shown in the list:

```terminal
flutter emulators --launch YOUR_EMULATOR_ID
```

After the simulator or emulator starts, run `flutter devices` again to confirm that it is available, and then run:

```terminal
flutter run -d YOUR_DEVICE_ID
```

---

## Patient Example Account

Currently, one example user account is kept in the database for testing:

Email: patient1@try.com
Password: password1

You can then use this account to log in and test the main functions of the app.

---

## Notes

- The Raspberry Pi vehicle-side software has already been deployed on the vehicle.
- The full robot functions require the physical smart vehicle hardware.
- If you only run the back-end and Flutter app without the vehicle connected, some robot-related functions such as live camera view, vehicle control, and robot status may not work.
- For Direct Connection mode, make sure the device running the back-end and/or mobile app is connected to the Raspberry Pi hotspot.
- For LAN mode, make sure the Raspberry Pi, back-end device, and mobile app device are under the same local network.