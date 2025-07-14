# Smartthings BambuLab Edge Driver

Not Tested. Dont install

https://callaway.smartthings.com/channels/31e1f421-55b7-4df3-9ca4-7f0ab93c927a

Driver Model

https://github.com/againtalent/SmartThings-Klipper

## Running Tests

This repository uses [busted](https://olivinelabs.com/busted/) to run Lua
unit tests located in the `tests/` directory. To run the tests locally:

```bash
sudo apt-get update && sudo apt-get install -y luarocks
sudo luarocks install busted
busted tests
```

The test suite validates that project JSON files can be loaded with `dkjson`.
