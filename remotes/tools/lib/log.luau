--> Colored output for the lune scripts.

local stdio = require("@lune/stdio")

local function paint(color: stdio.Color, message: string): string
    return stdio.color(color) .. message .. stdio.color("reset")
end

local log = {}

function log.step(message: string)
    print(paint("cyan", `-> {message}`))
end

function log.info(message: string)
    print(paint("white", `   {message}`))
end

function log.ok(message: string)
    print(paint("green", `   {message}`))
end

function log.warn(message: string)
    -- trap: Avoid warn() because it prefixes the message with [WARN] and makes
    -- the output taller.
    stdio.ewrite(paint("yellow", `   {message}`) .. "\n")
end

function log.err(message: string)
    print(paint("red", `   {message}`))
end

return log
