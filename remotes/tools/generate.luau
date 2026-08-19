--> Read a `*RemotesSchema.luau` declaration, and write everything it implies.
--
-- Usage:
--   lune run lune/remotes.luau -- features/Currency/Shared/CurrencyRemotesSchema.luau
--   lune run lune/remotes.luau -- Currency        (a feature name works too)
--   lune run lune/remotes.luau -- features        (every declaration under it)
-- Options:
--   --prune   delete instance files the schema no longer names
--   --dry     print what would happen, write nothing
--
-- `CurrencyRemotesSchema.luau` is written by hand and holds `export type Remotes`.
-- From it this writes:
--
--   * <dir>/Remotes/<Name>.model.json   with the className the type implies
--   * <dir>/CurrencyRemotes.luau        the barrel, in full
--
-- Blink's arrangement without the DSL: a declaration nobody generates, and
-- output nobody edits. The barrel is overwritten whole, so there is no marked
-- region to respect and no way to lose hand-written work inside it -- an
-- earlier version spliced a block into the declaration file itself, which mixed
-- the two.
--
-- The barrel names no payload type. It annotates its table with `Remotes` and
-- casts each instance to `any`; the annotation is what makes a remote missing
-- from the barrel an error, and `any` is what gets past the invariance of table
-- properties (the sourcemap types the instance as `RemoteEvent`, which is not
-- the same type as `Instance & {...}` in an invariant position). So a payload
-- type is written exactly once, in the declaration.

local fs = require("@lune/fs")
local log = require("./lib/log")
local luauType = require("./lib/luauType")
local process = require("@lune/process")

-- 1. Arguments ---------------------------------------------------------------

local target: string? = nil
local prune = false
local dry = false

local i = 1
while i <= #process.args do
    local arg = process.args[i]

    if arg == "--prune" then
        prune = true
    elseif arg == "--dry" then
        dry = true
    elseif arg == "--" then
        -- separator from `just`, ignore
    elseif string.sub(arg, 1, 2) == "--" then
        log.warn(`unknown option ignored: {arg}`)
    elseif target == nil then
        target = arg
    else
        log.warn(`extra argument ignored: {arg}`)
    end

    i += 1
end

if target == nil then
    log.err("usage: lune run lune/remotes.luau -- <XRemotesSchema.luau | directory | FeatureName>")
    process.exit(1)
end

-- 2. What a payload type says about the instance ------------------------------

-- Convention, not configuration: the instances sit in a `Remotes` folder next
-- to the declaration.
local INSTANCES_FOLDER = "Remotes"

-- Shim name -> the Roblox class that backs it. The one-way shims are the ones
-- to reach for; both map onto a plain RemoteEvent, since direction is a fact
-- about the type, not about the instance.
--
-- A shim that is not listed is refused rather than guessed: creating an instance
-- of the wrong class fails at runtime, far from here.
local CLASS_NAMES: { [string]: string } = {
    ToClient = "RemoteEvent",
    ToServer = "RemoteEvent",
    RemoteEvent = "RemoteEvent",
    UnreliableToClient = "UnreliableRemoteEvent",
    UnreliableRemoteEvent = "UnreliableRemoteEvent",
    RemoteFunction = "RemoteFunction",
}

local function classNameOf(fieldType: string): string?
    -- `RemoteTypes.ToClient<number>` or a bare `ToClient<...>`.
    local name = string.match(fieldType, "([%a_][%w_]*)%s*<")
    return if name then CLASS_NAMES[name] else nil
end

-- 3. Generating ---------------------------------------------------------------

local written: { string } = {}
local updated: { string } = {}
local orphans: { string } = {}

local function put(path: string, contents: string)
    if fs.metadata(path).exists then
        if fs.readFile(path) == contents then
            return
        end
        if not dry then
            fs.writeFile(path, contents)
        end
        table.insert(updated, path)
        return
    end

    if not dry then
        fs.writeFile(path, contents)
    end
    table.insert(written, path)
end

local function generateFor(schemaPath: string)
    local dir, schemaName = string.match(schemaPath, "^(.*)[/\\]([^/\\]+)%.luau$")
    if not dir or not schemaName then
        log.warn(`skipped {schemaPath} -- not a .luau path`)
        return
    end

    -- CurrencyRemotesSchema -> CurrencyRemotes
    local barrelName = string.gsub(schemaName :: string, "Schema$", "")
    local fields = luauType.fields(fs.readFile(schemaPath), "Remotes")

    if #fields == 0 then
        log.warn(schemaPath .. ": no `export type Remotes` with named fields")
        return
    end

    -- 3a. The instance files.
    local instancesDir = `{dir}/{INSTANCES_FOLDER}`
    local expected: { [string]: true } = {}
    local named: { string } = {}

    for _, field in fields do
        local className = classNameOf(field.luauType)
        if not className then
            log.warn(`{schemaPath}: cannot tell the class of "{field.name}" from "{field.luauType}" -- skipped`)
            continue
        end

        expected[`{field.name}.model.json`] = true
        table.insert(named, field.name)

        if not dry then
            fs.writeDir(instancesDir)
        end
        -- Plain concatenation: an interpolated string would need every brace of
        -- the JSON escaped.
        put(`{instancesDir}/{field.name}.model.json`, '{\n  "className": "' .. className .. '"\n}\n')
    end

    -- 3b. Instances the schema no longer names.
    if fs.metadata(instancesDir).exists then
        for _, entry in fs.readDir(instancesDir) do
            if expected[entry] or not string.match(entry, "%.model%.json$") then
                continue
            end

            local path = `{instancesDir}/{entry}`
            table.insert(orphans, path)
            if prune and not dry then
                fs.removeFile(path)
            end
        end
    end

    -- 3c. The barrel, in full.
    local lines = {
        `-- Generated by lune/remotes.luau from {schemaName}.luau -- do not edit.`,
        `--`,
        `-- Add or remove a remote in {schemaName}.luau, then run \`just remotes\`.`,
        ``,
        `local {schemaName} = require(script.Parent.{schemaName})`,
        ``,
        `local remotes: {schemaName}.Remotes = ` .. "{",
    }

    for _, name in named do
        table.insert(lines, `    {name} = script.Parent.{INSTANCES_FOLDER}.{name} :: any,`)
    end

    table.insert(lines, "}")
    table.insert(lines, ``)
    table.insert(lines, `return remotes`)
    table.insert(lines, ``)

    put(`{dir}/{barrelName}.luau`, table.concat(lines, "\n"))
end

-- 4. Walking the target -------------------------------------------------------

local function findSchemas(root: string, into: { string })
    for _, entry in fs.readDir(root) do
        local path = `{root}/{entry}`
        if fs.metadata(path).kind == "dir" then
            findSchemas(path, into)
        elseif string.match(entry, "RemotesSchema%.luau$") then
            table.insert(into, path)
        end
    end
end

-- A bare name means a feature: `just remotes Currency` rather than the whole
-- path. Only tried when the argument is not a path that exists, so a real path
-- always wins.
local function resolveTarget(value: string): string
    if fs.metadata(value).exists then
        return value
    end

    local asFeature = `features/{value}`
    if fs.metadata(asFeature).exists then
        return asFeature
    end

    return value
end

local targetPath = resolveTarget(target :: string)
local metadata = fs.metadata(targetPath)

if not metadata.exists then
    log.err(`no such path: {targetPath}`)
    process.exit(1)
end

local schemas: { string } = {}

if metadata.kind == "dir" then
    findSchemas(targetPath, schemas)
    if #schemas == 0 then
        log.err(`no *RemotesSchema.luau found under {targetPath}`)
        process.exit(1)
    end
else
    table.insert(schemas, targetPath)
end

log.step(`reading {#schemas} schema{if #schemas == 1 then "" else "s"}`)

for _, path in schemas do
    generateFor(path)
end

-- 5. Report -------------------------------------------------------------------

for _, path in written do
    log.ok(`{if dry then "would write" else "wrote"} {path}`)
end

for _, path in updated do
    log.ok(`{if dry then "would update" else "updated"} {path}`)
end

for _, path in orphans do
    if prune then
        log.ok(`{if dry then "would delete" else "deleted"} {path} (not in the schema any more)`)
    else
        log.warn(`{path} is not in the schema any more -- delete it, or re-run with --prune`)
    end
end

if #written == 0 and #updated == 0 then
    log.info("everything up to date")
end
