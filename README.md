# Bambu Lab Edge Driver

This project provides an experimental [SmartThings Edge](https://developer.smartthings.com/docs/edge-device-drivers) driver for Bambu Lab 3D printers. It discovers printers on the local network via SSDP and exposes a simple status capability in the SmartThings app.

The driver now stores two persistent fields on each discovered device:

- `status` – textual status for the printer, defaulting to `desconhecido`.
- `ip` – IP address for the printer based on the "IP da Impressora" preference.

These values are initialized when the device is added so the driver always has valid defaults.

## Preferences

Two preferences control how the driver connects to your printer:

- `printerIp` – IP address of the printer.
- `printerPort` – network port used for connections (defaults to `8883`).

You can set these options in the SmartThings app by opening the printer device, tapping the **︙** menu, choosing **Settings**, and editing the **IP da Impressora** and **Porta** fields.

## Requirements

- A SmartThings hub running firmware **0.47** or higher with Edge driver support.
- A Bambu Lab printer connected to the same local network as the hub.

## Installation

1. Enroll in the public channel and install the driver on your hub:
   <https://callaway.smartthings.com/channels/31e1f421-55b7-4df3-9ca4-7f0ab93c927a>
2. After installation, use the SmartThings mobile app to add a device and start discovery. The printer should appear automatically.

*This driver is a work in progress and may not function in all environments.*

## Running Tests

The test suite is written with [Busted](https://olivinelabs.com/busted/). To run the tests locally:

```bash
# Install dependencies
sudo apt-get install lua5.4 luarocks
sudo luarocks install busted

# Execute the tests
busted -o gtest -v tests
```

The CI workflow runs these same tests automatically for every pull request.

## Packaging Notes

If you receive an error like `Permissions have been modified` when running
`smartthings edge:drivers:package`, it means the permissions in `config.yaml`
were changed after the driver was initially published. Create a new package by
updating the `packageKey` in `config.yaml` before packaging again.

## License

This project is licensed under the [MIT License](LICENSE).
