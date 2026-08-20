--> Read a `*RemotesSchema.luau` declaration, and write everything it implies.
--
-- Usage:
--   lune run generate.luau -- <path/to/XRemotesSchema.luau>
--   lune run generate.luau -- <directory>      (every declaration under it)
--   lune run generate.luau -- <FeatureName>    (resolved under --features-root)
--
-- Options:
--   --prune                 delete instance files no declaration of the run names
--   --dry                   print what would happen, write nothing
--   --instances <name>      instances folder next to the declaration (Remotes)
--   --instances-dir <path>  put the instance files here instead
--   --instances-path <expr> how the barrel reaches them (script.Parent.<instances>)
--   --features-root <dir>   where a bare FeatureName is looked up (features)
--   --schema-suffix <s>     what marks a declaration (RemotesSchema.luau)
--   --barrel <name>         name the module instead of deriving it
--   --prune-root <dir>      where the orphan inventory is read from (.)
--
-- Each option's constraints are enforced below with an error that says what it
-- wanted; ../README.md says why they exist.
--
-- `CurrencyRemotesSchema.luau` is written by hand and holds `export type Remotes`.
-- From it this writes:
--
--   * <dir>/<instances>/<Name>.model.json   with the className the type implies
--   * CurrencyRemotes.luau                  the barrel, overwritten whole
--
-- Overwritten whole, so there is no marked region to respect and no
-- hand-written work to lose inside them.
--
-- Why any of this is shaped the way it is -- the two path options, the suffix
-- rule, the `any` cast in the barrel -- is in ../README.md. It is not repeated
-- here, because two copies of an explanation drift.

local fs = require("@lune/fs")
local log = require("./lib/log")
local luauType = require("./lib/luauType")
local process = require("@lune/process")

-- 1. Arguments ---------------------------------------------------------------

local target: string? = nil
local prune = false
local dry = false

-- Defaults, not requirements. Both describe the layout this grew in, so a
-- project using that layout passes nothing.
local instancesFolder = "Remotes"
local featuresRoot = "features"
local schemaSuffix = "RemotesSchema.luau"

-- No default: absent means "next to the declaration", which is not a path this
-- can spell until it has read one.
local instancesDir: string? = nil
local instancesPath: string? = nil
local barrelOverride: string? = nil

-- Where the orphan inventory is read from. "." because the question is what no
-- declaration ANYWHERE names, and a narrower root is how you delete a sibling's
-- instances by accident.
local pruneRoot = "."

local USAGE = "usage: lune run generate.luau -- <XRemotesSchema.luau | directory | FeatureName> "
    .. "[--prune] [--dry] [--instances <name>] [--instances-dir <path>] [--instances-path <expr>] "
    .. "[--features-root <dir>] [--schema-suffix <s>] [--barrel <name>] [--prune-root <dir>]"

local i = 1
while i <= #process.args do
    local arg = process.args[i]

    -- An option that takes a value consumes the next argument. Reading it past
    -- the end is the difference between a clear error and a silent default, so
    -- it is checked rather than assumed.
    local function value(): string
        local next = process.args[i + 1]
        if next == nil or string.sub(next, 1, 2) == "--" then
            log.err(`{arg} needs a value`)
            process.exit(1)
        end
        i += 1
        return next :: string
    end

    if arg == "--prune" then
        prune = true
    elseif arg == "--dry" then
        dry = true
    elseif arg == "--instances" then
        instancesFolder = value()
    elseif arg == "--instances-dir" then
        instancesDir = value()
    elseif arg == "--instances-path" then
        instancesPath = value()
    elseif arg == "--barrel" then
        barrelOverride = value()
    elseif arg == "--prune-root" then
        pruneRoot = value()
    elseif arg == "--features-root" then
        featuresRoot = value()
    elseif arg == "--schema-suffix" then
        schemaSuffix = value()
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
    log.err(USAGE)
    process.exit(1)
end

-- The barrel drops a trailing "Schema" from the declaration's name, so a suffix
-- that does not end in one would make the scan and the naming disagree. When
-- --barrel names the module outright nothing is derived, and the rule has
-- nothing left to protect.
if barrelOverride == nil and string.sub(schemaSuffix, -#"Schema.luau") ~= "Schema.luau" then
    log.err(`--schema-suffix must end in "Schema.luau", got "{schemaSuffix}"`)
    process.exit(1)
end

-- Moving the files without saying where they land in the datamodel leaves the
-- barrel pointing at where they used to be. Rojo may well map them back to the
-- old place, so this is a warning and not an error -- but it is a mistake far
-- more often than it is a mapping.
if instancesDir ~= nil and instancesPath == nil then
    log.warn("--instances-dir without --instances-path: the barrel still reads script.Parent." .. instancesFolder)
end

-- 2. What a payload type says about the instance ------------------------------

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

-- Instance files every schema of this run accounts for, per directory. Pruning
-- reads this once all the schemas have been read, because two schemas may write
-- into the same directory and neither knows what the other claims.
local claims: { [string]: { [string]: true } } = {}

--[==[
    How the barrel reaches the instances, and the line that has to precede it.

    `script.Parent.Remotes` needs nothing. `ReplicatedStorage.Remotes` needs the
    service fetched first -- indexing `game` directly works but yields to
    GetService everywhere else in a Roblox codebase, and generated code that
    does not look like written code invites being rewritten by hand.
]==]
local SERVICES: { [string]: true } = {
    ReplicatedStorage = true,
    ReplicatedFirst = true,
    ServerScriptService = true,
    ServerStorage = true,
    StarterGui = true,
    StarterPack = true,
    StarterPlayer = true,
    Lighting = true,
    SoundService = true,
    Players = true,
    Workspace = true,
    TextChatService = true,
}

local function datamodelAccess(): (string?, string)
    local path = instancesPath or `script.Parent.{instancesFolder}`
    local head = string.match(path, "^([%a_][%w_]*)")

    if head == nil or head == "script" or head == "game" then
        return nil, path
    end

    -- An unrecognised head would become `game:GetService("Remotes")`, which
    -- throws the first time the barrel is required -- in game, far from here.
    -- Refusing costs a message now instead of a runtime error later.
    if not SERVICES[head] then
        log.err(
            `--instances-path starts with "{head}", which is not a service. `
                .. `Use a service name, or start the path with script.`
        )
        process.exit(1)
    end

    return `local {head} = game:GetService("{head}")`, path
end

--[==[
    One directory, one spelling.

    `./sib/Remotes` and `sib/Remotes` are the same folder and different table
    keys, and the inventory is looked up by key. Without this the lookup misses,
    the run falls back to its own narrow claim set, and a sibling's instances
    read as orphans -- the exact deletion the inventory exists to prevent.
]==]
local function normalise(path: string): string
    local out = string.gsub(path, "\\", "/")
    out = string.gsub(out, "//+", "/")
    while string.sub(out, 1, 2) == "./" do
        out = string.sub(out, 3)
    end
    return out
end

local function generateFor(schemaPath: string)
    local dir, schemaName = string.match(schemaPath, "^(.*)[/\\]([^/\\]+)%.luau$")
    if not dir or not schemaName then
        log.warn(`skipped {schemaPath} -- not a .luau path`)
        return
    end

    -- CurrencyRemotesSchema -> CurrencyRemotes, unless --barrel said otherwise.
    local barrelName = barrelOverride or string.gsub(schemaName :: string, "Schema$", "")

    -- The barrel is written whole, so a name equal to the declaration's would
    -- overwrite the one file nobody generates -- silently, reported as an
    -- update. Reachable through --barrel, and also without it when a name has
    -- no trailing "Schema" for the gsub to drop.
    if barrelName == schemaName then
        log.err(
            `{schemaPath}: the barrel would be named {barrelName}.luau and overwrite `
                .. `the declaration. Name the declaration <Something>Schema.luau, or pass --barrel.`
        )
        process.exit(1)
    end
    local fields = luauType.fields(fs.readFile(schemaPath), "Remotes")

    if #fields == 0 then
        log.warn(schemaPath .. ": no `export type Remotes` with named fields")
        return
    end

    -- 3a. The instance files.
    local targetDir = normalise(instancesDir or `{dir}/{instancesFolder}`)
    local expected = claims[targetDir] or {}
    claims[targetDir] = expected
    local named: { string } = {}

    for _, field in fields do
        local className = classNameOf(field.luauType)
        if not className then
            log.warn(`{schemaPath}: cannot tell the class of "{field.name}" from "{field.luauType}" -- skipped`)
            continue
        end

        local entry = `{field.name}.model.json`
        if expected[entry] then
            -- Two declarations feeding one folder and naming the same remote:
            -- the second put wins, and its className may differ from the first.
            log.warn(
                `{schemaPath}: "{field.name}" is already claimed in {targetDir} by another `
                    .. `declaration -- remote names are global once the folder is`
            )
        end
        expected[entry] = true
        table.insert(named, field.name)

        if not dry then
            fs.writeDir(targetDir)
        end
        -- Plain concatenation: an interpolated string would need every brace of
        -- the JSON escaped.
        put(`{targetDir}/{field.name}.model.json`, '{\n  "className": "' .. className .. '"\n}\n')
    end

    -- 3b. The barrel, in full.
    local prelude, access = datamodelAccess()

    local lines = {
        `-- Generated from {schemaName}.luau by luau-cookbook/remotes -- do not edit.`,
        `--`,
        `-- Add or remove a remote in {schemaName}.luau, then re-run the generator.`,
        ``,
    }

    if prelude then
        table.insert(lines, prelude)
        table.insert(lines, ``)
    end

    table.insert(lines, `local {schemaName} = require(script.Parent.{schemaName})`)
    table.insert(lines, ``)
    table.insert(lines, `local remotes: {schemaName}.Remotes = ` .. "{")

    for _, name in named do
        table.insert(lines, `    {name} = {access}.{name} :: any,`)
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
        if string.sub(entry, 1, 1) == "." then
            continue
        elseif fs.metadata(path).kind == "dir" then
            findSchemas(path, into)
        elseif #entry > #schemaSuffix and string.sub(entry, -#schemaSuffix) == schemaSuffix then
            table.insert(into, path)
        end
    end
end

-- A bare name means a feature: `Currency` rather than the whole path. Only
-- tried when the argument is not a path that exists, so a real path always
-- wins and no layout assumption can shadow one.
local function resolveTarget(value: string): string
    if fs.metadata(value).exists then
        return value
    end

    local asFeature = `{featuresRoot}/{value}`
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

-- One name cannot serve several declarations: each would write the barrel over
-- the last, and the survivor would be whichever the walk reached last.
if barrelOverride ~= nil and metadata.kind == "dir" then
    log.err("--barrel names a single module, so it needs a single declaration, not a directory")
    process.exit(1)
end

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

-- 4b. Instances no declaration accounts for.
--
-- What makes a file an orphan is that NO declaration names it -- not that the
-- declarations this run happened to generate for do not. Those are different
-- sets the moment two declarations share an instances folder, and a folder is
-- shared by default whenever two declarations are file siblings. Pruning on the
-- narrower set deletes another feature's remotes, which is the failure this
-- whole arrangement exists to prevent, so the inventory is rebuilt from every
-- declaration under --prune-root rather than from the run.
local function claimedBy(schemaPath: string): (string?, { [string]: true }?)
    local dir = string.match(schemaPath, "^(.*)[/][^/]+%.luau$")
    if not dir then
        return nil, nil
    end

    local fields = luauType.fields(fs.readFile(schemaPath), "Remotes")
    if #fields == 0 then
        return nil, nil
    end

    local set: { [string]: true } = {}
    for _, field in fields do
        if classNameOf(field.luauType) then
            set[`{field.name}.model.json`] = true
        end
    end
    return normalise(instancesDir or `{dir}/{instancesFolder}`), set
end

local inventory: { [string]: { [string]: true } } = {}
local unreadable: { string } = {}

local everySchema: { string } = {}
if fs.metadata(pruneRoot).exists then
    findSchemas(pruneRoot, everySchema)
end

for _, path in everySchema do
    local directory, set = claimedBy(path)
    if not directory or not set then
        table.insert(unreadable, path)
        continue
    end

    local held = inventory[directory] or {}
    inventory[directory] = held
    for entry in set do
        held[entry] = true
    end
end

-- A declaration mid-edit claims nothing, and everything it owns would read as
-- an orphan. Deleting on that basis costs files for a typo, so the run stops
-- instead. Reporting is safe and still happens.
if prune and #unreadable > 0 then
    for _, path in unreadable do
        log.err(`cannot read {path}`)
    end
    log.err(
        `refusing to prune: {#unreadable} declaration(s) unreadable, so the inventory `
            .. `is incomplete and an orphan cannot be told from a file they own`
    )
    process.exit(1)
end

for directory in claims do
    if not fs.metadata(directory).exists then
        continue
    end

    local held = inventory[directory] or claims[directory]
    for _, entry in fs.readDir(directory) do
        if held[entry] or not string.match(entry, "%.model%.json$") then
            continue
        end

        local path = `{directory}/{entry}`
        table.insert(orphans, path)
        if prune and not dry then
            fs.removeFile(path)
        end
    end
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
