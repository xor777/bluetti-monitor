from __future__ import annotations

import asyncio
import io
import json
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from bleak.exc import (
    BleakBluetoothNotAvailableError,
    BleakBluetoothNotAvailableReason,
)

from spike import bluetti_probe


class BluetoothErrorTest(unittest.TestCase):
    def test_denied_access_returns_actionable_error(self) -> None:
        denied = BleakBluetoothNotAvailableError(
            "Bluetooth access is denied",
            BleakBluetoothNotAvailableReason.DENIED_BY_USER,
        )
        stderr = io.StringIO()

        with (
            patch.object(sys, "argv", ["bluetti_probe.py", "scan"]),
            patch.object(
                bluetti_probe.BleakScanner,
                "discover",
                AsyncMock(side_effect=denied),
            ),
            redirect_stderr(stderr),
        ):
            try:
                result: int | str = bluetti_probe.main()
            except Exception as error:  # Captures the current broken behavior.
                result = f"raised {type(error).__name__}"

        self.assertEqual(4, result)
        self.assertIn("System Settings", stderr.getvalue())
        self.assertIn("Privacy & Security", stderr.getvalue())

    def test_scan_formats_bleak_3_advertisement_without_connectable(self) -> None:
        device = SimpleNamespace(name="PR100V200000001")
        advertisement = SimpleNamespace(
            local_name="PR100V200000001",
            rssi=-42,
            service_uuids=["0000ff00-0000-1000-8000-00805f9b34fb"],
            manufacturer_data={1: b"\x01\x02"},
            service_data={},
        )
        stdout = io.StringIO()

        with (
            patch.object(
                bluetti_probe.BleakScanner,
                "discover",
                AsyncMock(return_value={"DEVICE-UUID": (device, advertisement)}),
            ),
            redirect_stdout(stdout),
        ):
            try:
                result: int | str = asyncio.run(
                    bluetti_probe.scan(seconds=0.1, show_all=True)
                )
            except Exception as error:  # Captures the current broken behavior.
                result = f"raised {type(error).__name__}"

        self.assertEqual(0, result)
        payload = json.loads(stdout.getvalue())
        self.assertEqual("DEVICE-UUID", payload[0]["address"])
        self.assertEqual(-42, payload[0]["rssi_dbm"])

    def test_read_serializes_decimal_telemetry_as_json_number(self) -> None:
        stdout = io.StringIO()

        with (
            patch.object(
                bluetti_probe.DeviceReader,
                "read",
                AsyncMock(return_value={"ac_input_voltage": Decimal("230.1")}),
            ),
            redirect_stdout(stdout),
        ):
            try:
                result: int | str = asyncio.run(
                    bluetti_probe.read("DEVICE-UUID", "PR100V2")
                )
            except Exception as error:  # Captures the current broken behavior.
                result = f"raised {type(error).__name__}"

        self.assertEqual(0, result)
        self.assertEqual(230.1, json.loads(stdout.getvalue())["ac_input_voltage"])


class PowerStateDetectorTest(unittest.TestCase):
    def test_reports_loss_after_two_consecutive_low_voltage_samples(self) -> None:
        detector = bluetti_probe.PowerStateDetector(confirm_samples=2)

        self.assertIsNone(detector.observe(233.0))
        self.assertEqual("AC_INPUT_ONLINE", detector.observe(233.0))
        self.assertIsNone(detector.observe(0.0))
        self.assertEqual("AC_INPUT_LOST", detector.observe(0.0))
        self.assertIsNone(detector.observe(0.0))

    def test_reports_restoration_after_two_consecutive_online_samples(self) -> None:
        detector = bluetti_probe.PowerStateDetector(confirm_samples=2)
        detector.observe(233.0)
        detector.observe(233.0)
        detector.observe(0.0)
        detector.observe(0.0)

        self.assertIsNone(detector.observe(232.0))
        self.assertEqual("AC_INPUT_RESTORED", detector.observe(232.0))

    def test_uncertain_voltage_breaks_a_pending_transition(self) -> None:
        detector = bluetti_probe.PowerStateDetector(confirm_samples=2)
        detector.observe(233.0)
        detector.observe(233.0)

        self.assertIsNone(detector.observe(0.0))
        self.assertIsNone(detector.observe(75.0))
        self.assertIsNone(detector.observe(0.0))
        self.assertEqual("AC_INPUT_LOST", detector.observe(0.0))


if __name__ == "__main__":
    unittest.main()
