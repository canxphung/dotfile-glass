-- Chạy thử config Hyprland của Glass với một `hl` giả.
-- Bắt lỗi runtime (gọi nil, nối chuỗi với nil...) và phím tắt bị trùng,
-- những thứ `luac -p` không thấy. Không kiểm tra được giá trị option có
-- hợp lệ với Hyprland hay không; phần đó cần test trên máy thật.
--
--   lua tests/lua-smoke.lua <đường dẫn tới hyprland.lua đã cài>

local entry = assert(arg[1], "cần đường dẫn tới hyprland.lua")

local binds = {}
local envs = {}
local errors = {}

local function fail(msg)
    errors[#errors + 1] = msg
end

-- Proxy nhận mọi lời gọi hl.x.y(...) và trả về một bảng mô tả.
local function proxy(path)
    return setmetatable({}, {
        __index = function(_, key)
            return proxy(path .. "." .. key)
        end,
        __call = function(_, ...)
            return { call = path, args = { ... } }
        end,
    })
end

hl = proxy("hl")

rawset(hl, "bind", function(keys, action, opts)
    if type(keys) ~= "string" then
        fail("hl.bind: phím không phải chuỗi")
        return
    end
    if type(action) ~= "table" and type(action) ~= "function" then
        fail("hl.bind(" .. keys .. "): action không hợp lệ")
    end
    if opts ~= nil and type(opts) ~= "table" then
        fail("hl.bind(" .. keys .. "): flags phải là bảng")
    end
    if binds[keys] then
        fail("phím tắt bị trùng: " .. keys)
    end
    binds[keys] = true
    return proxy("keybind")
end)

rawset(hl, "config", function(tbl)
    if type(tbl) ~= "table" then
        fail("hl.config: tham số phải là bảng")
    end
end)

rawset(hl, "env", function(name, value)
    if type(name) ~= "string" or type(value) ~= "string" then
        fail("hl.env: cần (tên, giá trị) là chuỗi")
        return
    end
    envs[#envs + 1] = name
end)

rawset(hl, "on", function(event, cb)
    if type(event) ~= "string" or type(cb) ~= "function" then
        fail("hl.on: cần (tên sự kiện, hàm)")
    end
end)

-- require kiểu Hyprland: nhận đường dẫn tuyệt đối, có hoặc không có .lua.
local loaded = {}
require = function(name)
    local path = name:match("%.lua$") and name or (name .. ".lua")
    if loaded[path] == nil then
        local chunk, err = loadfile(path)
        if not chunk then
            error("require(" .. name .. "): " .. err, 2)
        end
        local ok, result = pcall(chunk)
        if not ok then
            fail("lỗi khi chạy " .. path .. ": " .. tostring(result))
            result = false
        end
        loaded[path] = result == nil and true or result
    end
    return loaded[path]
end

local ok, err = pcall(dofile, entry)
if not ok then
    fail("lỗi khi chạy " .. entry .. ": " .. tostring(err))
end

local count = 0
for _ in pairs(binds) do
    count = count + 1
end
if count < 20 then
    fail("chỉ có " .. count .. " phím tắt, có vẻ binds.lua không chạy hết")
end

-- Mọi biến hl.env phải được glass-session chép vào systemd --user, không
-- thì dịch vụ và app mở từ start menu không thấy (vd. mất bộ gõ).
local imported = {}
for name in (os.getenv("GLASS_SESSION_ENV") or ""):gmatch("%S+") do
    imported[name] = true
end
for _, name in ipairs(envs) do
    if not imported[name] then
        fail("biến " .. name .. " đặt bằng hl.env nhưng không có trong session_env của glass-session")
    end
end

if #errors > 0 then
    for _, e in ipairs(errors) do
        io.stderr:write("FAIL: ", e, "\n")
    end
    os.exit(1)
end

print(("lua: ok (%d phím tắt)"):format(count))
