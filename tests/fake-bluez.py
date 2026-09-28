#!/usr/bin/env python3
"""BlueZ giả cho test shell (tests/shell-smoke.sh).

Giữ tên org.bluez trên system bus (DBUS_SYSTEM_BUS_ADDRESS, trong test là bus
riêng) với một adapter hci0 và phần API mà Quickshell.Bluetooth và agent ghép
nối của glassd dùng: bật/tắt, tìm thiết bị, ghép nối, kết nối, tin cậy, quên.
Có sẵn một tai nghe đã ghép nối; tìm thiết bị thì thấy thêm:

  Loa Phòng Khách  ghép nối hỏi agent RequestConfirmation(123456)
  Bàn phím Glass   ghép nối gọi agent DisplayPasskey(654321), 1,5 giây sau
                   coi như đã gõ xong trên bàn phím

Các việc đáng kiểm tra được ghi từng dòng vào file log.

Cách dùng: fake-bluez.py LOG
"""

import asyncio
import os
import sys

from dbus_next import BusType, Message, MessageType, PropertyAccess, Variant
from dbus_next.aio import MessageBus
from dbus_next.errors import DBusError
from dbus_next.service import ServiceInterface, dbus_property, method

ADAPTER = "/org/bluez/hci0"
OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
AGENT = "org.bluez.Agent1"
PASSKEY = {"confirm": 123456, "display": 654321}

# địa chỉ, tên, icon, class, cách ghép nối; thiết bị đầu đã ghép nối sẵn.
DEVICES = [
    ("00:1A:7D:DA:71:01", "Tai nghe Aero", "audio-headset", 0x240404, "confirm"),
    ("00:1A:7D:DA:71:02", "Loa Phòng Khách", "audio-card", 0x240414, "confirm"),
    ("00:1A:7D:DA:71:03", "Bàn phím Glass", "input-keyboard", 0x002540, "display"),
]

log_path = sys.argv[1]
bus = None
agent = None  # (tên duy nhất trên bus, đường dẫn) của agent mặc định
last_sender = None


def log(line):
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def ro():
    return dbus_property(access=PropertyAccess.READ)


async def call_agent(member, signature, body):
    if agent is None:
        return None
    return await bus.call(
        Message(destination=agent[0], path=agent[1], interface=AGENT, member=member, signature=signature, body=body)
    )


def interfaces_added(path, interfaces):
    # Quickshell nghe InterfacesAdded trên đường dẫn của ObjectManager ("/"),
    # còn dbus-next tự phát từ đường dẫn của đối tượng, nên phát thêm ở đây.
    bus.send(
        Message.new_signal("/", OBJECT_MANAGER, "InterfacesAdded", "oa{sa{sv}}", [path, interfaces])
    )


def interfaces_removed(path, names):
    bus.send(Message.new_signal("/", OBJECT_MANAGER, "InterfacesRemoved", "oas", [path, names]))


class AgentManager(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.AgentManager1")

    @method()
    def RegisterAgent(self, path: "o", capability: "s"):
        global agent
        agent = (last_sender, path)
        log(f"agent {capability}")

    @method()
    def RequestDefaultAgent(self, path: "o"):
        log("default agent")

    @method()
    def UnregisterAgent(self, path: "o"):
        global agent
        agent = None
        log("agent gone")


class Battery(ServiceInterface):
    def __init__(self, percent):
        super().__init__("org.bluez.Battery1")
        self.percent = percent

    @ro()
    def Percentage(self) -> "y":
        return self.percent

    @ro()
    def Source(self) -> "s":
        return "HFP"


class Device(ServiceInterface):
    def __init__(self, address, alias, icon, klass, pairing, paired):
        super().__init__("org.bluez.Device1")
        self.address = address
        self.alias = alias
        self.icon = icon
        self.klass = klass
        self.pairing = pairing
        self.path = f"{ADAPTER}/dev_{address.replace(':', '_')}"
        self.paired = paired
        self.trusted = paired
        self.connected = False
        self.cancel = None
        self.battery = Battery(80) if paired else None

    def props(self):
        return {
            "Address": Variant("s", self.address),
            "AddressType": Variant("s", "public"),
            "Name": Variant("s", self.alias),
            "Alias": Variant("s", self.alias),
            "Class": Variant("u", self.klass),
            "Icon": Variant("s", self.icon),
            "Paired": Variant("b", self.paired),
            "Bonded": Variant("b", self.paired),
            "Trusted": Variant("b", self.trusted),
            "Blocked": Variant("b", False),
            "LegacyPairing": Variant("b", False),
            "Connected": Variant("b", self.connected),
            "ServicesResolved": Variant("b", self.connected),
            "WakeAllowed": Variant("b", False),
            "UUIDs": Variant("as", []),
            "Adapter": Variant("o", ADAPTER),
        }

    def export(self):
        bus.export(self.path, self)
        interfaces = {self.name: self.props()}
        if self.battery:
            bus.export(self.path, self.battery)
            interfaces[self.battery.name] = {"Percentage": Variant("y", self.battery.percent)}
        interfaces_added(self.path, interfaces)

    def unexport(self):
        names = [self.name] + ([self.battery.name] if self.battery else [])
        interfaces_removed(self.path, names)
        bus.unexport(self.path)

    def set_connected(self, on):
        self.connected = on
        self.emit_properties_changed({"Connected": on, "ServicesResolved": on})

    @ro()
    def Address(self) -> "s":
        return self.address

    @ro()
    def AddressType(self) -> "s":
        return "public"

    @ro()
    def Name(self) -> "s":
        return self.alias

    @dbus_property()
    def Alias(self) -> "s":
        return self.alias

    @Alias.setter
    def Alias(self, value: "s"):
        self.alias = value
        self.emit_properties_changed({"Alias": value})

    @ro()
    def Class(self) -> "u":
        return self.klass

    @ro()
    def Icon(self) -> "s":
        return self.icon

    @ro()
    def Paired(self) -> "b":
        return self.paired

    @ro()
    def Bonded(self) -> "b":
        return self.paired

    @dbus_property()
    def Trusted(self) -> "b":
        return self.trusted

    @Trusted.setter
    def Trusted(self, value: "b"):
        self.trusted = value
        self.emit_properties_changed({"Trusted": value})
        log(f"trusted {self.alias} {'yes' if value else 'no'}")

    @dbus_property()
    def Blocked(self) -> "b":
        return False

    @Blocked.setter
    def Blocked(self, value: "b"):
        pass

    @dbus_property()
    def WakeAllowed(self) -> "b":
        return False

    @WakeAllowed.setter
    def WakeAllowed(self, value: "b"):
        pass

    @ro()
    def LegacyPairing(self) -> "b":
        return False

    @ro()
    def Connected(self) -> "b":
        return self.connected

    @ro()
    def ServicesResolved(self) -> "b":
        return self.connected

    @ro()
    def UUIDs(self) -> "as":
        return []

    @ro()
    def Adapter(self) -> "o":
        return ADAPTER

    @method()
    async def Pair(self):
        if self.paired:
            raise DBusError("org.bluez.Error.AlreadyExists", "Đã ghép nối")
        if agent is None:
            raise DBusError("org.bluez.Error.AuthenticationFailed", "Không có agent")
        self.cancel = asyncio.get_running_loop().create_future()
        log(f"pair {self.alias}")
        passkey = PASSKEY[self.pairing]
        try:
            if self.pairing == "confirm":
                ask = asyncio.ensure_future(call_agent("RequestConfirmation", "ou", [self.path, passkey]))
                done, _ = await asyncio.wait({ask, self.cancel}, return_when=asyncio.FIRST_COMPLETED)
                if self.cancel in done:
                    await call_agent("Cancel", "", [])
                    raise DBusError("org.bluez.Error.AuthenticationCanceled", "Đã huỷ")
                reply = ask.result()
                if reply.message_type == MessageType.ERROR:
                    log(f"pair {self.alias} {reply.error_name}")
                    raise DBusError("org.bluez.Error.AuthenticationRejected", "Người dùng từ chối")
            else:
                await call_agent("DisplayPasskey", "ouq", [self.path, passkey, 0])
                try:
                    await asyncio.wait_for(asyncio.shield(self.cancel), 1.5)
                    await call_agent("Cancel", "", [])
                    raise DBusError("org.bluez.Error.AuthenticationCanceled", "Đã huỷ")
                except asyncio.TimeoutError:
                    pass
        finally:
            self.cancel = None
        self.paired = True
        self.emit_properties_changed({"Paired": True, "Bonded": True})
        log(f"paired {self.alias}")

    @method()
    def CancelPairing(self):
        if self.cancel is None:
            raise DBusError("org.bluez.Error.DoesNotExist", "Không đang ghép nối")
        log(f"cancel {self.alias}")
        self.cancel.set_result(None)

    @method()
    async def Connect(self):
        if not adapter.powered:
            raise DBusError("org.bluez.Error.NotReady", "Adapter đang tắt")
        await asyncio.sleep(0.2)
        self.set_connected(True)
        log(f"connected {self.alias}")

    @method()
    def Disconnect(self):
        self.set_connected(False)
        log(f"disconnected {self.alias}")


class Adapter(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.Adapter1")
        self.powered = True
        self.discovering = False
        self.devices = {}

    def props(self):
        return {
            "Address": Variant("s", "00:1A:7D:DA:70:00"),
            "AddressType": Variant("s", "public"),
            "Name": Variant("s", "glass-test"),
            "Alias": Variant("s", "glass-test"),
            "Class": Variant("u", 0x6C010C),
            "Powered": Variant("b", self.powered),
            "PowerState": Variant("s", "on" if self.powered else "off"),
            "Discoverable": Variant("b", False),
            "DiscoverableTimeout": Variant("u", 180),
            "Pairable": Variant("b", True),
            "PairableTimeout": Variant("u", 0),
            "Discovering": Variant("b", self.discovering),
            "UUIDs": Variant("as", []),
        }

    def add(self, entry, paired=False):
        address, alias, icon, klass, pairing = entry
        device = Device(address, alias, icon, klass, pairing, paired)
        self.devices[device.path] = device
        device.export()

    def set_discovering(self, on):
        self.discovering = on
        self.emit_properties_changed({"Discovering": on})

    async def discover(self):
        await asyncio.sleep(0.3)
        present = {d.address for d in self.devices.values()}
        for entry in DEVICES:
            if self.discovering and entry[0] not in present:
                self.add(entry)

    @ro()
    def Address(self) -> "s":
        return "00:1A:7D:DA:70:00"

    @ro()
    def AddressType(self) -> "s":
        return "public"

    @ro()
    def Name(self) -> "s":
        return "glass-test"

    @dbus_property()
    def Alias(self) -> "s":
        return "glass-test"

    @Alias.setter
    def Alias(self, value: "s"):
        pass

    @ro()
    def Class(self) -> "u":
        return 0x6C010C

    @dbus_property()
    def Powered(self) -> "b":
        return self.powered

    @Powered.setter
    def Powered(self, value: "b"):
        if value == self.powered:
            return
        self.powered = value
        if not value:
            for device in self.devices.values():
                if device.connected:
                    device.set_connected(False)
            if self.discovering:
                self.set_discovering(False)
        self.emit_properties_changed({"Powered": value, "PowerState": "on" if value else "off"})
        log("power " + ("on" if value else "off"))

    @ro()
    def PowerState(self) -> "s":
        return "on" if self.powered else "off"

    @dbus_property()
    def Discoverable(self) -> "b":
        return False

    @Discoverable.setter
    def Discoverable(self, value: "b"):
        pass

    @dbus_property()
    def DiscoverableTimeout(self) -> "u":
        return 180

    @DiscoverableTimeout.setter
    def DiscoverableTimeout(self, value: "u"):
        pass

    @dbus_property()
    def Pairable(self) -> "b":
        return True

    @Pairable.setter
    def Pairable(self, value: "b"):
        pass

    @dbus_property()
    def PairableTimeout(self) -> "u":
        return 0

    @PairableTimeout.setter
    def PairableTimeout(self, value: "u"):
        pass

    @ro()
    def Discovering(self) -> "b":
        return self.discovering

    @ro()
    def UUIDs(self) -> "as":
        return []

    @method()
    def StartDiscovery(self):
        if not self.powered:
            raise DBusError("org.bluez.Error.NotReady", "Adapter đang tắt")
        if not self.discovering:
            self.set_discovering(True)
            log("discovery on")
            asyncio.ensure_future(self.discover())

    @method()
    def StopDiscovery(self):
        if self.discovering:
            self.set_discovering(False)
            log("discovery off")

    @method()
    def SetDiscoveryFilter(self, properties: "a{sv}"):
        pass

    @method()
    def GetDiscoveryFilters(self) -> "as":
        return ["UUIDs", "RSSI", "Pathloss", "Transport", "DuplicateData", "Discoverable", "Pattern"]

    @method()
    def RemoveDevice(self, path: "o"):
        device = self.devices.pop(path, None)
        if device is None:
            raise DBusError("org.bluez.Error.DoesNotExist", "Không có thiết bị")
        device.unexport()
        log(f"removed {device.alias}")


def remember_sender(msg):
    # Phương thức của ServiceInterface không thấy người gọi; ghi lại để
    # AgentManager biết gọi agent ở đâu.
    global last_sender
    if msg.message_type == MessageType.METHOD_CALL:
        last_sender = msg.sender


async def main():
    global bus, adapter
    address = os.environ.get("DBUS_SYSTEM_BUS_ADDRESS")
    bus = await (MessageBus(bus_address=address) if address else MessageBus(bus_type=BusType.SYSTEM)).connect()
    bus.add_message_handler(remember_sender)

    adapter = Adapter()
    bus.export("/org/bluez", AgentManager())
    bus.export(ADAPTER, adapter)
    interfaces_added(ADAPTER, {adapter.name: adapter.props()})
    adapter.add(DEVICES[0], paired=True)

    await bus.request_name("org.bluez")
    log("ready")
    await bus.wait_for_disconnect()


asyncio.run(main())
