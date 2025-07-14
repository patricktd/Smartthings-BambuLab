# Smartthings BambuLab Edge Driver

Not tested; don't install yet.

https://callaway.smartthings.com/channels/31e1f421-55b7-4df3-9ca4-7f0ab93c927a

Driver Model

https://github.com/againtalent/SmartThings-Klipper

## Building and Installing

This repository uses the SmartThings Edge framework. To create a package that can be installed on your hub, run:

```
smartthings edge:package
```

The generated package will appear in the `edge-driver-bambulab` directory. Upload the `*.zip` file through the SmartThings CLI or web interface.

## Testing

After installing the driver, initiate device discovery from the mobile app. The driver will attempt to locate Bambu Lab printers on your local network using SSDP and create a device for each printer found.
