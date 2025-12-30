# Bambu Lab Edge Driver

This project provides an experimental [SmartThings Edge](https://developer.smartthings.com/docs/edge-device-drivers) driver for Bambu Lab 3D printers. It discovers printers on the local network via SSDP and exposes a simple status capability in the SmartThings app.

These values are initialized when the device is added so the driver always has valid defaults.

## Preferences
**Note:** The serial number can be up to 15 characters and the access code up to 8 characters.

Two preferences control how the driver connects to your printer:

- `printerIp` – IP address of the printer.
- `printerPort` – network port used for connections (defaults to `8883`).

You can set these options in the SmartThings app by opening the printer device, tapping the **︙** menu, choosing **Settings**, and editing the **IP da Impressora** and **Porta** fields.

## Requirements

- A SmartThings hub running firmware **0.47** or higher with Edge driver support.
- A Bambu Lab printer connected to the same local network as the hub.

## License

This project is licensed under the [MIT License](LICENSE).
