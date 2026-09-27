-- Bàn phím, chuột, touchpad, gesture.

hl.config({
    input = {
        kb_layout          = "us",
        numlock_by_default = true,
        follow_mouse       = 1,
        sensitivity        = 0,

        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            disable_while_typing = true,
        },
    },
})

-- Vuốt 3 ngón ngang để đổi workspace.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})
