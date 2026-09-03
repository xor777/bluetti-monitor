# BLUETTI BLE spike (throwaway)

This probe answers two questions before the standalone application is designed:

1. Does macOS discover the station and expose the expected BLUETTI GATT service?
2. Can the known, read-only `PR100V2` registers be decoded after the V2 handshake?

The probe never sends Modbus write/control function `0x06`. The encrypted V2
handshake and Modbus read requests (`0x03`) still have to be sent through the BLE
write characteristic; "read-only" refers to device state, not to the GATT packet
direction.

## Setup

Python 3.12 is known to work on the development Mac.

```bash
python3 -m venv .venv
.venv/bin/pip install -r spike/requirements.txt
```

macOS must grant Bluetooth access to the application launching Python. Check:

`System Settings -> Privacy & Security -> Bluetooth`

Keep the BLUETTI mobile app disconnected while probing; a BLE peripheral often
accepts only one active central connection.

## Discover

```bash
.venv/bin/python spike/bluetti_probe.py scan --seconds 20
```

On macOS, CoreBluetooth reports an opaque UUID rather than the device's physical
MAC address. Use that UUID as `--address` below.

## Read known Premium 100 V2 telemetry

```bash
.venv/bin/python spike/bluetti_probe.py read --address DEVICE_UUID
```

## Watch for loss and restoration of external AC power

```bash
.venv/bin/python spike/bluetti_probe.py listen \
  --address DEVICE_UUID \
  --stop-after-restore
```

The listener keeps one encrypted BLE connection open and reads AC input voltage
and power once per second. It emits `AC_INPUT_LOST` after two consecutive samples
at or below 50 V, `AC_INPUT_RESTORED` after two samples at or above 100 V, and
reports a Bluetooth failure separately as `BLE_DISCONNECTED`.

The currently mapped read-only fields are:

- device type;
- device serial number;
- battery state of charge;
- DC input and output power;
- AC input and output power;
- AC input voltage.

This code is intentionally a feasibility probe, not the production application.
The implemented MVP uses a native Swift core and macOS menu-bar UI at the project
root, following the final YAGNI technology decision.
