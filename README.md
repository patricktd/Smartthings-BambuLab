# Bambu Lab 3D Printer Edge Driver

This is an experimental [SmartThings Edge](https://developer.smartthings.com/docs/edge-device-drivers) driver for Bambu Lab 3D printers, designed to provide real-time status monitoring and control directly within the SmartThings app.

It uses the local MQTT interface of the printer for fast and private communication, without relying on the Bambu Lab cloud.

## Features

*   **Real-time Status**: View current printer status (Printing, Idle, Paused, Offline, etc.).
*   **Progress Monitoring**: Live print progress (%) and estimated remaining time.
*   **Temperature**: Monitor heatbed and nozzle temperatures.
*   **Fan Control**: View speeds for Cooling, Auxiliary, and Chamber fans.
*   **AMS Integration**: See which filament slots are active (Generic support).
* Control the Chamber Light.

*   **Detailed Info**:
    *   Current file name.
    *   Layer information (Current / Total).
    *   Print finish time estimation.

## Supported Printers

This driver is designed to work with Bambu Lab printers that support local MQTT:

*   **Bambu Lab X1 Series** (X1C, X1)
*   **Bambu Lab P1 Series** (P1P, P1S) - Tested
*   **Bambu Lab A1 Series** (A1, A1 Mini) - Tested

## Installation & Setup

1.  **Install the Driver**: Enroll in the channel and install the "Bambu Lab 3D Printers" driver to your SmartThings Hub.
2.  **Add the Bridge**:
    *   In the SmartThings app, run a "Scan for Nearby Devices".
    *   A device named **"Bambu Lab Bridge"** should be discovered. Add it.
3.  **Add Your Printer**:
    *   Open the "Bambu Lab Bridge" device.
    *   Tap the button to **"Add New Printer"**.
    *   A new "Bambu Lab Printer" device will appear in your room (it may take a few seconds).
4.  **Configure Printer**:
    *   Open the newly created **"Bambu Lab Printer"** device.
    *   Tap the **Settings (⋮)** menu (three dots in the top right) and select **Settings**.
    *   Enter the following information found on your printer's screen (Network / WiFi settings):
        *   **Printer IP**: The local IP address of your printer.
        *   **Serial Number**: The 15-character serial number.
        *   **Access Code**: The 8-digit access code (found in the printer's network menu).
    *   **Save** the settings.

The driver will automatically connect and start reporting status.

## Troubleshooting

*   **Offline/No Data**: Double-check the IP, Serial, and Access Code. Ensure your Hub and Printer are on the same local network.
*   **"Generic" Model**: The driver identifies primarily as a generic Bambu Lab printer to ensure compatibility across models.

## License

This project is licensed under the [Apache 2.0 License](LICENSE).

## Credits

Developed by **Patrick Teixeira (PATTETECH)**.
