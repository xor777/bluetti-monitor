#!/usr/bin/env python3
"""Throwaway, read-only BLUETTI Premium 100 V2 feasibility probe."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from collections.abc import Mapping
from datetime import datetime
from decimal import Decimal
from typing import Any

from bleak import BleakScanner
from bleak.exc import BleakBluetoothNotAvailableError
from bleak_retry_connector import BleakClientWithServiceCache, establish_connection
from bluetti_bt_lib.bluetooth.device_reader import DeviceReader, DeviceReaderConfig
from bluetti_bt_lib.const import NOTIFY_UUID
from bluetti_bt_lib.registers import ReadableRegisters
from bluetti_bt_lib.utils.device_builder import build_device
from bluetti_bt_lib.utils.device_info import get_type_by_bt_name


DEFAULT_MODEL = "PR100V2"


class PowerStateDetector:
    def __init__(
        self,
        confirm_samples: int = 2,
        lost_below_volts: float = 50.0,
        restored_above_volts: float = 100.0,
    ) -> None:
        if confirm_samples < 1:
            raise ValueError("confirm_samples must be positive")
        self.confirm_samples = confirm_samples
        self.lost_below_volts = lost_below_volts
        self.restored_above_volts = restored_above_volts
        self.state: str | None = None
        self._candidate: str | None = None
        self._candidate_samples = 0

    def observe(self, voltage: float) -> str | None:
        if voltage <= self.lost_below_volts:
            candidate = "offline"
        elif voltage >= self.restored_above_volts:
            candidate = "online"
        else:
            self._candidate = None
            self._candidate_samples = 0
            return None

        if candidate == self.state:
            self._candidate = None
            self._candidate_samples = 0
            return None

        if candidate == self._candidate:
            self._candidate_samples += 1
        else:
            self._candidate = candidate
            self._candidate_samples = 1

        if self._candidate_samples < self.confirm_samples:
            return None

        previous = self.state
        self.state = candidate
        self._candidate = None
        self._candidate_samples = 0

        if candidate == "offline":
            return "AC_INPUT_LOST"
        if previous == "offline":
            return "AC_INPUT_RESTORED"
        return "AC_INPUT_ONLINE"


def _json_default(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def _hex_map(values: Mapping[Any, bytes]) -> dict[str, str]:
    return {str(key): bytes(value).hex() for key, value in values.items()}


async def scan(seconds: float, show_all: bool) -> int:
    discovered = await BleakScanner.discover(timeout=seconds, return_adv=True)
    rows: list[dict[str, Any]] = []

    for address, (device, advertisement) in discovered.items():
        name = advertisement.local_name or device.name
        model = get_type_by_bt_name(name) if name else None
        if not show_all and model is None and not (name or "").startswith("PBOX"):
            continue

        rows.append(
            {
                "name": name,
                "model": model,
                "address": address,
                "rssi_dbm": advertisement.rssi,
                "service_uuids": advertisement.service_uuids,
                "manufacturer_data": _hex_map(advertisement.manufacturer_data),
                "service_data": {
                    key: bytes(value).hex()
                    for key, value in advertisement.service_data.items()
                },
            }
        )

    rows.sort(key=lambda row: row["rssi_dbm"], reverse=True)
    print(json.dumps(rows, indent=2, ensure_ascii=False))
    return 0 if rows else 2


async def read(address: str, model: str) -> int:
    device = build_device(f"{model}00000000")
    if device is None:
        raise SystemExit(f"Unsupported model: {model}")

    reader = DeviceReader(
        address,
        device,
        asyncio.Future,
        DeviceReaderConfig(timeout=60, use_encryption=True),
    )
    data = await reader.read()
    if data is None:
        print("No telemetry received", flush=True)
        return 3

    print(
        json.dumps(
            data,
            indent=2,
            ensure_ascii=False,
            sort_keys=True,
            default=_json_default,
        )
    )
    return 0


def _timestamp() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


async def _wait_for_v2_handshake(reader: DeviceReader, seconds: float = 15) -> None:
    async with asyncio.timeout(seconds):
        while not reader.encryption.is_ready_for_commands:
            await asyncio.sleep(0.05)


async def _read_one(
    reader: DeviceReader,
    device: Any,
    register: ReadableRegisters,
) -> dict[str, Any]:
    response = await reader._async_send_command(register)
    if not response or not register.is_valid_response(response):
        raise RuntimeError(f"invalid response for register {register.starting_address}")
    return device.parse(register.starting_address, register.parse_response(response))


async def listen(
    address: str,
    model: str,
    interval: float,
    confirm_samples: int,
    duration: float,
    stop_after_restore: bool,
) -> int:
    device = build_device(f"{model}00000000")
    if device is None:
        raise SystemExit(f"Unsupported model: {model}")

    peripheral = await BleakScanner.find_device_by_address(address, timeout=10)
    if peripheral is None:
        print(f"{_timestamp()} EVENT BLE_DEVICE_NOT_FOUND", flush=True)
        return 6

    client = await establish_connection(
        BleakClientWithServiceCache,
        peripheral,
        peripheral.name or model,
        max_attempts=3,
    )
    reader = DeviceReader(
        address,
        device,
        asyncio.Future,
        DeviceReaderConfig(timeout=60, use_encryption=True),
        ble_client=client,
    )
    reader.client = client
    detector = PowerStateDetector(confirm_samples=confirm_samples)
    voltage_register = ReadableRegisters(1314, 1)
    power_register = ReadableRegisters(146, 1)
    saw_loss = False
    loop = asyncio.get_running_loop()
    deadline = loop.time() + duration if duration > 0 else None

    try:
        await client.start_notify(NOTIFY_UUID, reader._notification_handler)
        reader.has_notifier = True
        await _wait_for_v2_handshake(reader)
        print(f"{_timestamp()} EVENT BLE_CONNECTED", flush=True)

        while deadline is None or loop.time() < deadline:
            voltage_data = await _read_one(reader, device, voltage_register)
            power_data = await _read_one(reader, device, power_register)
            voltage = float(voltage_data["ac_input_voltage"])
            power = int(power_data["ac_input_power"])
            event = detector.observe(voltage)
            state = detector.state or "confirming"
            print(
                f"{_timestamp()} SAMPLE ac_input_voltage={voltage:.1f}V "
                f"ac_input_power={power}W state={state}",
                flush=True,
            )

            if event is not None:
                print(
                    f"{_timestamp()} EVENT {event} "
                    f"ac_input_voltage={voltage:.1f}V ac_input_power={power}W",
                    flush=True,
                )
                if event == "AC_INPUT_ONLINE":
                    print(f"{_timestamp()} LISTENER_READY", flush=True)
                elif event == "AC_INPUT_LOST":
                    saw_loss = True
                elif event == "AC_INPUT_RESTORED" and saw_loss and stop_after_restore:
                    print(f"{_timestamp()} EXPERIMENT_COMPLETE", flush=True)
                    return 0

            await asyncio.sleep(interval)

        print(f"{_timestamp()} EVENT LISTENER_TIMEOUT", flush=True)
        return 5
    except TimeoutError:
        print(f"{_timestamp()} EVENT BLE_HANDSHAKE_TIMEOUT", flush=True)
        return 6
    except Exception as error:
        print(
            f"{_timestamp()} EVENT BLE_DISCONNECTED error={type(error).__name__}: {error}",
            flush=True,
        )
        return 6
    finally:
        if reader.has_notifier:
            try:
                await client.stop_notify(NOTIFY_UUID)
            except Exception:
                pass
        await client.disconnect()


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    scan_parser = commands.add_parser("scan", help="scan nearby BLE advertisements")
    scan_parser.add_argument("--seconds", type=float, default=20)
    scan_parser.add_argument(
        "--all",
        action="store_true",
        help="show every named BLE device, not just recognized BLUETTI devices",
    )

    read_parser = commands.add_parser("read", help="read known telemetry registers")
    read_parser.add_argument("--address", required=True)
    read_parser.add_argument("--model", default=DEFAULT_MODEL)

    listen_parser = commands.add_parser(
        "listen", help="watch AC input voltage and report power transitions"
    )
    listen_parser.add_argument("--address", required=True)
    listen_parser.add_argument("--model", default=DEFAULT_MODEL)
    listen_parser.add_argument("--interval", type=float, default=1.0)
    listen_parser.add_argument("--confirm-samples", type=int, default=2)
    listen_parser.add_argument("--duration", type=float, default=180.0)
    listen_parser.add_argument("--stop-after-restore", action="store_true")
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "scan":
            return asyncio.run(scan(args.seconds, args.all))
        if args.command == "read":
            return asyncio.run(read(args.address, args.model.upper()))
        return asyncio.run(
            listen(
                args.address,
                args.model.upper(),
                args.interval,
                args.confirm_samples,
                args.duration,
                args.stop_after_restore,
            )
        )
    except BleakBluetoothNotAvailableError as error:
        print(
            "Bluetooth is unavailable to this process: "
            f"{error}. Open System Settings -> Privacy & Security -> Bluetooth "
            "and allow the application that launches Python.",
            file=sys.stderr,
        )
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
