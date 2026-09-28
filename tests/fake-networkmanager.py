#!/usr/bin/env python3
"""NetworkManager giả cho test shell (tests/shell-smoke.sh).

Giữ tên org.freedesktop.NetworkManager trên system bus (DBUS_SYSTEM_BUS_ADDRESS,
trong test là bus riêng) và dựng đủ phần API mà Quickshell.Networking và
secret agent của glassd dùng: một card Wi-Fi thấy vài mạng, một card mạng dây
chưa cắm; kết nối, ngắt, quên, bật/tắt Wi-Fi; mạng có mật khẩu thì hỏi agent
đã đăng ký (GetSecrets) như NetworkManager thật, sai mật khẩu thì hỏi lại với
cờ REQUEST_NEW.

Các việc đáng kiểm tra được ghi từng dòng vào file log (xem log()).

Cách dùng: fake-networkmanager.py LOG
"""

import asyncio
import os
import sys
import time
import uuid

from dbus_next import BusType, Message, MessageType, PropertyAccess, Variant
from dbus_next.aio import MessageBus
from dbus_next.errors import DBusError
from dbus_next.service import ServiceInterface, dbus_property, method, signal

NM = "org.freedesktop.NetworkManager"
BASE = "/org/freedesktop/NetworkManager"
SECRET_AGENT = NM + ".SecretAgent"
AGENT_PATH = BASE + "/SecretAgent"
SECURITY = "802-11-wireless-security"

# NMDeviceState
UNAVAILABLE, DISCONNECTED, PREPARE, CONFIG, NEED_AUTH, IP_CONFIG = 20, 30, 40, 50, 60, 70
ACTIVATED, DEACTIVATING, FAILED = 100, 110, 120
# NMDeviceStateReason
R_NONE, R_NO_SECRETS, R_USER_REQUESTED = 0, 7, 39
# NMActiveConnectionState và lý do
AC_ACTIVATING, AC_ACTIVATED, AC_DEACTIVATING, AC_DEACTIVATED = 1, 2, 3, 4
ACR_NONE, ACR_USER_DISCONNECTED, ACR_DEVICE_DISCONNECTED = 1, 2, 3
# NMState
NM_DISCONNECTED, NM_CONNECTING, NM_CONNECTED = 20, 40, 70
# Cờ GetSecrets
ALLOW_INTERACTION, REQUEST_NEW = 0x1, 0x2
# Cờ AP: PRIVACY; RSN: PAIR_CCMP | GROUP_CCMP | KEY_MGMT_PSK
AP_PRIVACY, RSN_PSK = 0x1, 0x8 | 0x80 | 0x100
# Card hỗ trợ WEP, TKIP, CCMP, WPA, RSN, 2.4/5 GHz
WIFI_CAPS = 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x200 | 0x400

# Mạng thấy được: tên, sóng (%), mật khẩu (None: mạng mở).
NETWORKS = [
    ("Nhà Mình", 82, "matkhau123"),
    ("Quán Cà Phê", 64, None),
    ("Hàng Xóm", 38, "khongbiet"),
]
# Mạng đã lưu từ trước (được nối bằng ActivateConnection, không hỏi gì).
SAVED = ["Quán Cà Phê"]

log_path = sys.argv[1]
bus = None
agent = None  # tên duy nhất trên bus của secret agent đã đăng ký
last_sender = None


def log(line):
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def boottime_ms():
    return int(time.clock_gettime(time.CLOCK_BOOTTIME) * 1000)


def ro():
    return dbus_property(access=PropertyAccess.READ)


class Manager(ServiceInterface):
    def __init__(self):
        super().__init__(NM)
        self.wireless = True
        self.check = True
        self.devices = []
        self.nm_state = NM_DISCONNECTED

    def refresh(self):
        actives = [d.active for d in self.devices if d.active]
        done = [a for a in actives if a.state == AC_ACTIVATED]
        state = NM_CONNECTED if done else NM_CONNECTING if actives else NM_DISCONNECTED
        changed = {
            "ActiveConnections": [a.path for a in actives],
            "PrimaryConnection": done[0].path if done else "/",
            "Connectivity": 4 if done else 1,
        }
        if state != self.nm_state:
            self.nm_state = state
            changed["State"] = state
            self.StateChanged(state)
        self.emit_properties_changed(changed)

    @dbus_property()
    def WirelessEnabled(self) -> "b":
        return self.wireless

    @WirelessEnabled.setter
    def WirelessEnabled(self, value: "b"):
        if value != self.wireless:
            self.wireless = value
            self.emit_properties_changed({"WirelessEnabled": value})
            asyncio.ensure_future(wifi.set_enabled(value))

    @ro()
    def WirelessHardwareEnabled(self) -> "b":
        return True

    @ro()
    def NetworkingEnabled(self) -> "b":
        return True

    @ro()
    def WwanEnabled(self) -> "b":
        return False

    @ro()
    def Version(self) -> "s":
        return "1.54.0"

    @ro()
    def State(self) -> "u":
        return self.nm_state

    @ro()
    def Connectivity(self) -> "u":
        return 4 if any(d.active and d.active.state == AC_ACTIVATED for d in self.devices) else 1

    @ro()
    def ConnectivityCheckAvailable(self) -> "b":
        return True

    @dbus_property()
    def ConnectivityCheckEnabled(self) -> "b":
        return self.check

    @ConnectivityCheckEnabled.setter
    def ConnectivityCheckEnabled(self, value: "b"):
        self.check = value
        self.emit_properties_changed({"ConnectivityCheckEnabled": value})

    @ro()
    def Devices(self) -> "ao":
        return [d.path for d in self.devices]

    @ro()
    def AllDevices(self) -> "ao":
        return [d.path for d in self.devices]

    @ro()
    def ActiveConnections(self) -> "ao":
        return [d.active.path for d in self.devices if d.active]

    @ro()
    def PrimaryConnection(self) -> "o":
        done = [d.active for d in self.devices if d.active and d.active.state == AC_ACTIVATED]
        return done[0].path if done else "/"

    @method()
    def GetDevices(self) -> "ao":
        return [d.path for d in self.devices]

    @method()
    def GetAllDevices(self) -> "ao":
        return [d.path for d in self.devices]

    @method()
    def CheckConnectivity(self) -> "u":
        return 4 if any(d.active and d.active.state == AC_ACTIVATED for d in self.devices) else 1

    @method()
    def ActivateConnection(self, connection: "o", device: "o", specific: "o") -> "o":
        conn = settings.find(connection)
        if conn is None:
            raise DBusError(NM + ".Manager.UnknownConnection", "Không có kết nối " + connection)
        log(f"activate {conn.ssid}")
        return wifi.start(conn).path

    @method()
    def AddAndActivateConnection(self, values: "a{sa{sv}}", device: "o", specific: "o") -> "oo":
        ap = wifi.ap_by_path(specific)
        if ap is None:
            raise DBusError(NM + ".Manager.UnknownConnection", "Không có điểm truy cập " + specific)
        psk = values.get(SECURITY, {}).get("psk")
        conn = settings.add(ap.ssid, ap.password is not None, psk.value if psk else None)
        log(f"add {ap.ssid}" + (" psk" if psk else ""))
        return [conn.path, wifi.start(conn).path]

    @method()
    def DeactivateConnection(self, active: "o"):
        if wifi.active and wifi.active.path == active:
            asyncio.ensure_future(wifi.deactivate(ACR_USER_DISCONNECTED))

    @signal()
    def DeviceAdded(self, path) -> "o":
        return path

    @signal()
    def DeviceRemoved(self, path) -> "o":
        return path

    @signal()
    def StateChanged(self, state) -> "u":
        return state


class AgentManager(ServiceInterface):
    def __init__(self):
        super().__init__(NM + ".AgentManager")

    @staticmethod
    def register(identifier):
        global agent
        agent = last_sender
        log(f"agent {identifier}")

    @method()
    def Register(self, identifier: "s"):
        self.register(identifier)

    @method()
    def RegisterWithCapabilities(self, identifier: "s", capabilities: "u"):
        self.register(identifier)

    @method()
    def Unregister(self):
        global agent
        agent = None
        log("agent gone")


class Settings(ServiceInterface):
    def __init__(self):
        super().__init__(NM + ".Settings")
        self.connections = []
        self.next = 1

    def find(self, path):
        return next((c for c in self.connections if c.path == path), None)

    def add(self, ssid, secured, psk=None, timestamp=0):
        conn = Connection(f"{BASE}/Settings/{self.next}", ssid, secured, psk, timestamp)
        self.next += 1
        self.connections.append(conn)
        bus.export(conn.path, conn)
        self.NewConnection(conn.path)
        self.emit_properties_changed({"Connections": [c.path for c in self.connections]})
        wifi.set_available()
        return conn

    def remove(self, conn):
        self.connections.remove(conn)
        conn.Removed()
        self.ConnectionRemoved(conn.path)
        self.emit_properties_changed({"Connections": [c.path for c in self.connections]})
        wifi.set_available()
        bus.unexport(conn.path, conn)

    @ro()
    def Connections(self) -> "ao":
        return [c.path for c in self.connections]

    @ro()
    def Hostname(self) -> "s":
        return "glass-test"

    @ro()
    def CanModify(self) -> "b":
        return True

    @method()
    def ListConnections(self) -> "ao":
        return [c.path for c in self.connections]

    @signal()
    def NewConnection(self, path) -> "o":
        return path

    @signal()
    def ConnectionRemoved(self, path) -> "o":
        return path


class Connection(ServiceInterface):
    """Một hồ sơ kết nối Wi-Fi. Mật khẩu giữ riêng, GetSettings không trả."""

    def __init__(self, path, ssid, secured, psk, timestamp):
        super().__init__(NM + ".Settings.Connection")
        self.path = path
        self.ssid = ssid
        self.secured = secured
        self.psk = psk
        self.uuid = str(uuid.uuid4())
        self.timestamp = timestamp

    def values(self):
        values = {
            "connection": {
                "id": Variant("s", self.ssid),
                "uuid": Variant("s", self.uuid),
                "type": Variant("s", "802-11-wireless"),
                "timestamp": Variant("t", self.timestamp),
            },
            "802-11-wireless": {
                "ssid": Variant("ay", self.ssid.encode()),
                "mode": Variant("s", "infrastructure"),
            },
        }
        if self.secured:
            values[SECURITY] = {"key-mgmt": Variant("s", "wpa-psk")}
        return values

    @ro()
    def Unsaved(self) -> "b":
        return False

    @ro()
    def Flags(self) -> "u":
        return 0

    @ro()
    def Filename(self) -> "s":
        return f"/etc/NetworkManager/system-connections/{self.ssid}.nmconnection"

    @method()
    def GetSettings(self) -> "a{sa{sv}}":
        return self.values()

    @method()
    def GetSecrets(self, setting: "s") -> "a{sa{sv}}":
        if setting == SECURITY and self.psk:
            return {SECURITY: {"psk": Variant("s", self.psk)}}
        return {}

    @method()
    def Update(self, values: "a{sa{sv}}"):
        psk = values.get(SECURITY, {}).get("psk")
        if psk:
            self.psk = psk.value
        log(f"update {self.ssid}" + (" psk" if psk else ""))
        self.Updated()

    @method()
    def ClearSecrets(self):
        self.psk = None
        self.Updated()

    @method()
    def Save(self):
        pass

    @method()
    def Delete(self):
        log(f"forget {self.ssid}")
        asyncio.ensure_future(self.delete())

    async def delete(self):
        if wifi.active and wifi.active.conn is self:
            await wifi.deactivate(ACR_USER_DISCONNECTED)
        settings.remove(self)

    @signal()
    def Updated(self):
        pass

    @signal()
    def Removed(self):
        pass


class Active(ServiceInterface):
    def __init__(self, path, conn, ap, device):
        super().__init__(NM + ".Connection.Active")
        self.path = path
        self.conn = conn
        self.ap = ap
        self.device = device
        self.state = AC_ACTIVATING
        self.dead = False
        self.asking = False

    def set_state(self, state, reason):
        self.state = state
        self.emit_properties_changed({"State": state})
        self.StateChanged(state, reason)

    @ro()
    def Connection(self) -> "o":
        return self.conn.path

    @ro()
    def SpecificObject(self) -> "o":
        return self.ap.path

    @ro()
    def Id(self) -> "s":
        return self.conn.ssid

    @ro()
    def Uuid(self) -> "s":
        return self.conn.uuid

    @ro()
    def Type(self) -> "s":
        return "802-11-wireless"

    @ro()
    def Devices(self) -> "ao":
        return [self.device]

    @ro()
    def State(self) -> "u":
        return self.state

    @ro()
    def StateFlags(self) -> "u":
        return 0

    @ro()
    def Default(self) -> "b":
        return self.state == AC_ACTIVATED

    @ro()
    def Vpn(self) -> "b":
        return False

    @signal()
    def StateChanged(self, state, reason) -> "uu":
        return [state, reason]


class AccessPoint(ServiceInterface):
    def __init__(self, index, ssid, strength, password):
        super().__init__(NM + ".AccessPoint")
        self.index = index
        self.path = f"{BASE}/AccessPoint/{index}"
        self.ssid = ssid
        self.strength = strength
        self.password = password

    @ro()
    def Ssid(self) -> "ay":
        return self.ssid.encode()

    @ro()
    def Strength(self) -> "y":
        return self.strength

    @ro()
    def Flags(self) -> "u":
        return AP_PRIVACY if self.password else 0

    @ro()
    def WpaFlags(self) -> "u":
        return 0

    @ro()
    def RsnFlags(self) -> "u":
        return RSN_PSK if self.password else 0

    @ro()
    def Mode(self) -> "u":
        return 2

    @ro()
    def Frequency(self) -> "u":
        return 2437

    @ro()
    def HwAddress(self) -> "s":
        return "02:00:00:00:02:%02X" % self.index

    @ro()
    def MaxBitrate(self) -> "u":
        return 144000

    @ro()
    def LastSeen(self) -> "i":
        return boottime_ms() // 1000


class Device(ServiceInterface):
    """Phần chung org.freedesktop.NetworkManager.Device của hai card."""

    def __init__(self, path, dtype, ifname, hw, state):
        super().__init__(NM + ".Device")
        self.path = path
        self.dtype = dtype
        # Không đặt self.name: ServiceInterface dùng nó làm tên interface.
        self.ifname = ifname
        self.hw = hw
        self.state = state
        self.reason = R_NONE
        self.available = []
        self.active = None

    def set_state(self, state, reason=R_NONE):
        old = self.state
        if old == state:
            return
        self.state, self.reason = state, reason
        self.emit_properties_changed({"State": state, "StateReason": [state, reason]})
        self.StateChanged(state, old, reason)

    def set_active(self, active):
        self.active = active
        self.emit_properties_changed({"ActiveConnection": active.path if active else "/"})

    @ro()
    def DeviceType(self) -> "u":
        return self.dtype

    @ro()
    def Interface(self) -> "s":
        return self.ifname

    @ro()
    def IpInterface(self) -> "s":
        return self.ifname

    @ro()
    def Driver(self) -> "s":
        return "fake"

    @ro()
    def HwAddress(self) -> "s":
        return self.hw

    @dbus_property()
    def Managed(self) -> "b":
        return True

    @Managed.setter
    def Managed(self, value: "b"):
        pass

    @dbus_property()
    def Autoconnect(self) -> "b":
        return True

    @Autoconnect.setter
    def Autoconnect(self, value: "b"):
        pass

    @ro()
    def State(self) -> "u":
        return self.state

    @ro()
    def StateReason(self) -> "(uu)":
        return [self.state, self.reason]

    @ro()
    def AvailableConnections(self) -> "ao":
        return self.available

    @ro()
    def ActiveConnection(self) -> "o":
        return self.active.path if self.active else "/"

    @ro()
    def InterfaceFlags(self) -> "u":
        # UP; card dây chưa cắm nên không có CARRIER.
        return 0x1

    @method()
    def Disconnect(self):
        if self.dtype == 2:
            log("disconnect")
            asyncio.ensure_future(wifi.deactivate(ACR_USER_DISCONNECTED))

    @signal()
    def StateChanged(self, new, old, reason) -> "uuu":
        return [new, old, reason]


class Wired(ServiceInterface):
    def __init__(self):
        super().__init__(NM + ".Device.Wired")

    @ro()
    def HwAddress(self) -> "s":
        return "02:00:00:00:01:01"

    @ro()
    def PermHwAddress(self) -> "s":
        return "02:00:00:00:01:01"

    @ro()
    def Speed(self) -> "u":
        return 0

    @ro()
    def Carrier(self) -> "b":
        return False


class Wireless(ServiceInterface):
    """Card Wi-Fi: điểm truy cập, quét, và toàn bộ luồng kết nối."""

    def __init__(self, device):
        super().__init__(NM + ".Device.Wireless")
        self.device = device
        self.aps = []
        self.active_ap = None
        self.last_scan = boottime_ms()

    @property
    def active(self):
        return self.device.active

    def add_aps(self):
        for i, (ssid, strength, password) in enumerate(NETWORKS, 1):
            ap = AccessPoint(i, ssid, strength, password)
            self.aps.append(ap)
            bus.export(ap.path, ap)
            self.AccessPointAdded(ap.path)
        self.emit_properties_changed({"AccessPoints": [a.path for a in self.aps]})

    def remove_aps(self):
        aps, self.aps = self.aps, []
        for ap in aps:
            self.AccessPointRemoved(ap.path)
            bus.unexport(ap.path, ap)
        self.emit_properties_changed({"AccessPoints": []})

    def ap_by_path(self, path):
        return next((a for a in self.aps if a.path == path), None)

    def ap_by_ssid(self, ssid):
        return next((a for a in self.aps if a.ssid == ssid), None)

    def set_available(self):
        self.device.available = [c.path for c in settings.connections] if manager.wireless else []
        self.device.emit_properties_changed({"AvailableConnections": self.device.available})

    def set_active_ap(self, ap):
        self.active_ap = ap
        self.emit_properties_changed({"ActiveAccessPoint": ap.path if ap else "/"})

    async def set_enabled(self, on):
        log("wifi " + ("on" if on else "off"))
        if on:
            self.device.set_state(DISCONNECTED)
            self.add_aps()
        else:
            await self.deactivate(ACR_DEVICE_DISCONNECTED)
            self.remove_aps()
            self.device.set_state(UNAVAILABLE)
        self.set_available()

    def start(self, conn):
        """Tạo kết nối đang hoạt động và chạy luồng kết nối ở nền."""
        ap = self.ap_by_ssid(conn.ssid)
        if ap is None:
            raise DBusError(NM + ".Manager.UnknownDevice", "Không thấy mạng " + conn.ssid)
        active = Active(f"{BASE}/ActiveConnection/{uuid.uuid4().hex[:8]}", conn, ap, self.device.path)
        asyncio.ensure_future(self.activate(active))
        return active

    async def activate(self, active):
        if self.active:
            await self.deactivate(ACR_USER_DISCONNECTED)
        bus.export(active.path, active)
        self.device.set_active(active)
        manager.refresh()
        self.device.set_state(PREPARE)
        # Cho shell kịp đọc kết nối mới trước khi có kết quả.
        await asyncio.sleep(0.3)
        if active.dead:
            return
        self.device.set_state(CONFIG)
        if active.ap.password and not await self.secrets(active):
            if not active.dead:
                await self.fail(active, R_NO_SECRETS)
            return
        self.device.set_state(IP_CONFIG)
        await asyncio.sleep(0.1)
        if active.dead:
            return
        active.conn.timestamp = int(time.time())
        self.device.set_state(ACTIVATED)
        self.set_active_ap(active.ap)
        active.set_state(AC_ACTIVATED, ACR_NONE)
        manager.refresh()
        log(f"connected {active.conn.ssid}")

    async def secrets(self, active):
        """Mật khẩu đã lưu đúng thì dùng luôn, không thì hỏi agent."""
        conn = active.conn
        if conn.psk == active.ap.password:
            return True
        flags = ALLOW_INTERACTION | (REQUEST_NEW if conn.psk else 0)
        for _ in range(3):
            self.device.set_state(NEED_AUTH)
            if agent is None:
                log(f"secrets {conn.ssid} no-agent")
                return False
            log(f"secrets {conn.ssid} flags={flags}")
            active.asking = True
            reply = await bus.call(
                Message(
                    destination=agent,
                    path=AGENT_PATH,
                    interface=SECRET_AGENT,
                    member="GetSecrets",
                    signature="a{sa{sv}}osasu",
                    body=[conn.values(), conn.path, SECURITY, [], flags],
                )
            )
            active.asking = False
            if active.dead:
                return False
            if reply.message_type == MessageType.ERROR:
                log(f"secrets {conn.ssid} error {reply.error_name}")
                return False
            psk = reply.body[0].get(SECURITY, {}).get("psk")
            conn.psk = psk.value if psk else None
            if conn.psk == active.ap.password:
                log(f"secrets {conn.ssid} ok")
                return True
            log(f"secrets {conn.ssid} wrong")
            flags = ALLOW_INTERACTION | REQUEST_NEW
            self.device.set_state(CONFIG)
            await asyncio.sleep(0.2)
        return False

    async def fail(self, active, reason):
        # Thứ tự như NetworkManager: thiết bị báo failed kèm lý do trước, rồi
        # kết nối đang hoạt động báo DeviceDisconnected.
        active.dead = True
        self.device.set_state(FAILED, reason)
        active.set_state(AC_DEACTIVATED, ACR_DEVICE_DISCONNECTED)
        log(f"failed {active.conn.ssid} reason={reason}")
        await asyncio.sleep(0.2)
        await self.drop(active)

    async def deactivate(self, reason):
        active = self.active
        if active is None or active.dead:
            return
        active.dead = True
        if active.asking and agent:
            await bus.call(
                Message(
                    destination=agent,
                    path=AGENT_PATH,
                    interface=SECRET_AGENT,
                    member="CancelGetSecrets",
                    signature="os",
                    body=[active.conn.path, SECURITY],
                )
            )
        active.set_state(AC_DEACTIVATING, reason)
        self.device.set_state(DEACTIVATING, R_USER_REQUESTED)
        await asyncio.sleep(0.1)
        active.set_state(AC_DEACTIVATED, reason)
        log(f"disconnected {active.conn.ssid}")
        await self.drop(active)

    async def drop(self, active):
        if self.active is active:
            self.device.set_active(None)
            self.set_active_ap(None)
            if self.device.state != UNAVAILABLE:
                self.device.set_state(DISCONNECTED)
            manager.refresh()
        await asyncio.sleep(0.5)
        bus.unexport(active.path, active)

    @ro()
    def HwAddress(self) -> "s":
        return self.device.hw

    @ro()
    def PermHwAddress(self) -> "s":
        return self.device.hw

    @ro()
    def Mode(self) -> "u":
        return 2

    @ro()
    def Bitrate(self) -> "u":
        return 144000 if self.active_ap else 0

    @ro()
    def AccessPoints(self) -> "ao":
        return [a.path for a in self.aps]

    @ro()
    def ActiveAccessPoint(self) -> "o":
        return self.active_ap.path if self.active_ap else "/"

    @ro()
    def WirelessCapabilities(self) -> "u":
        return WIFI_CAPS

    @ro()
    def LastScan(self) -> "x":
        return self.last_scan

    @method()
    def GetAccessPoints(self) -> "ao":
        return [a.path for a in self.aps]

    @method()
    def GetAllAccessPoints(self) -> "ao":
        return [a.path for a in self.aps]

    @method()
    def RequestScan(self, options: "a{sv}"):
        if not manager.wireless:
            raise DBusError(NM + ".Device.NotAllowed", "Wi-Fi đang tắt")
        self.last_scan = boottime_ms()
        self.emit_properties_changed({"LastScan": self.last_scan})
        log("scan")

    @signal()
    def AccessPointAdded(self, path) -> "o":
        return path

    @signal()
    def AccessPointRemoved(self, path) -> "o":
        return path


def remember_sender(msg):
    # Phương thức của ServiceInterface không thấy người gọi; ghi lại trước
    # khi dbus-next chuyển lời gọi đi để AgentManager biết agent ở đâu.
    global last_sender
    if msg.message_type == MessageType.METHOD_CALL:
        last_sender = msg.sender


async def main():
    global bus, manager, settings, wifi
    address = os.environ.get("DBUS_SYSTEM_BUS_ADDRESS")
    bus = await (MessageBus(bus_address=address) if address else MessageBus(bus_type=BusType.SYSTEM)).connect()
    bus.add_message_handler(remember_sender)

    manager = Manager()
    settings = Settings()
    wifi_device = Device(f"{BASE}/Devices/1", 2, "wlan0", "02:00:00:00:00:01", DISCONNECTED)
    wired_device = Device(f"{BASE}/Devices/2", 1, "enp3s0", "02:00:00:00:01:01", UNAVAILABLE)
    wifi = Wireless(wifi_device)
    manager.devices = [wifi_device, wired_device]

    bus.export(BASE, manager)
    bus.export(BASE + "/AgentManager", AgentManager())
    bus.export(BASE + "/Settings", settings)
    bus.export(wifi_device.path, wifi_device)
    bus.export(wifi_device.path, wifi)
    bus.export(wired_device.path, wired_device)
    bus.export(wired_device.path, Wired())
    wifi.add_aps()
    for ssid in SAVED:
        settings.add(ssid, wifi.ap_by_ssid(ssid).password is not None, timestamp=int(time.time()) - 86400)

    await bus.request_name(NM)
    log("ready")
    await bus.wait_for_disconnect()


asyncio.run(main())
