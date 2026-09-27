-- Hiệu ứng: nhanh, gọn, cửa sổ "nở" nhẹ khi mở như Aero.

hl.config({
    animations = {
        enabled = true,
    },
})

hl.curve("aero",   { type = "bezier", points = { {0.22, 1},  {0.36, 1} } })
hl.curve("linear", { type = "bezier", points = { {0, 0},     {1, 1}    } })
hl.curve("soft",   { type = "bezier", points = { {0.5, 0.5}, {0.75, 1} } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,  bezier = "default" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 3.5, bezier = "aero",   style = "popin 90%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2,   bezier = "linear", style = "popin 90%" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 4,   bezier = "aero" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 2,   bezier = "soft" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.5, bezier = "soft" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3,   bezier = "aero" })
hl.animation({ leaf = "border",        enabled = true, speed = 5,   bezier = "aero" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 3,   bezier = "aero",   style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 3.5, bezier = "aero",   style = "slidefade 12%" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,   bezier = "aero" })
