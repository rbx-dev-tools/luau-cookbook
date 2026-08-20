--> Read a `*RemotesSchema.luau` declaration, and write everything it implies.
--
-- Usage:
--   lune run generate.luau -- <path/to/XRemotesSchema.luau>
--   lune run generate.luau -- <directory>      (every declaration under it)
--   lune run generate.luau -- <FeatureName>    (resolved under --features-root)
--
-- Options:
--   --prune                 delete instance files the schema no longer names
--   --dry                   print what would happen, write nothing
--   --instances <name>      folder for the generated instances, next to the
--                           declaration (default: Remotes)
--   --instances-dir <path>  where the instance files go, when that is not next
--                           to the declaration. Overrides --instances.
--   --instances-path <expr> how the barrel reaches them in the datamodel
--                           (default: script.Parent.<instances>). A leading
--                           service name is resolved with GetService.
--   --features-root <dir>   where a bare FeatureName is looked up
--                           (default: features)
--   --schema-suffix <s>     filename suffix that marks a declaration when
--                           scanning a directory (default: RemotesSchema.luau).
--                           Must end in "Schema.luau", because the barrel is
--                           named by dropping that word -- unless --barrel
--                           names it outright.
--   --barrel <name>         name the generated module instead of deriving it.
--                           Single declaration only: a directory would write
--                           every barrel over the same file.
--
-- `CurrencyRemotesSchema.luau` is written by hand and holds `export type Remotes`.
-- From it this writes:
--
--   * <dir>/<instances>/<Name>.model.json   with the className the type implies
--   * <dir>/CurrencyRemotes.luau            the barrel, in full
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
-- type is written exactly once.
--
-- What is convention here and what is configurable: `export type Remotes` is
-- fixed, because it is what makes a declaration readable at all. The filename
-- suffix has a default rather than being fixed, and everything about WHERE
-- things live is an option, so this runs against a tree it did not grow in.
--
-- Where things live is two questions, not one, and an early version answered
-- them with a single option because the two coincide when everything is a
-- sibling. `--instances-dir` is a filesystem path; `--instances-path` is a
-- datamodel path. Rojo decides how one maps to the other, and it can map them
-- any way it likes, so nothing here can derive the second from the first.
--
-- The suffix is checked to end in "Schema.luau" rather than being free. Finding
-- a declaration and naming its barrel are two rules that have to agree, and an
-- unchecked suffix lets them drift: a file the scan skips still generates fine
-- when pointed at directly, which is a confusing way to learn about a typo.

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

local USAGE = "usage: lune run generate.luau -- <XRemotesSchema.luau | directory | FeatureName> "
    .. "[--prune] [--dry] [--instances <name>] [--instances-dir <path>] [--instances-path <expr>] "
    .. "[--features-root <dir>] [--schema-suffix <s>] [--barrel <name>]"

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
local function datamodelAccess(): (string?, string)
    local path = instancesPath or `script.Parent.{instancesFolder}`
    local head = string.match(path, "^([%a_][%w_]*)")

    if head == nil or head == "script" or head == "game" then
        return nil, path
    end

    return `local {head} = game:GetService("{head}")`, path
end

local function generateFor(schemaPath: string)
    local dir, schemaName = string.match(schemaPath, "^(.*)[/\\]([^/\\]+)%.luau$")
    if not dir or not schemaName then
        log.warn(`skipped {schemaPath} -- not a .luau path`)
        return
    end

    -- CurrencyRemotesSchema -> CurrencyRemotes, unless --barrel said otherwise.
    local barrelName = barrelOverride or string.gsub(schemaName :: string, "Schema$", "")
    local fields = luauType.fields(fs.readFile(schemaPath), "Remotes")

    if #fields == 0 then
        log.warn(schemaPath .. ": no `export type Remotes` with named fields")
        return
    end

    -- 3a. The instance files.
    local targetDir = instancesDir or `{dir}/{instancesFolder}`
    local expected = claims[targetDir] or {}
    claims[targetDir] = expected
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
        if fs.metadata(path).kind == "dir" then
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

-- A shared directory is only ever fully accounted for by a run that reads every
-- declaration feeding it. Reading one and pruning would delete the others'
-- instances -- the very thing the grouped pass exists to prevent, reintroduced
-- by aiming too narrowly.
if prune and instancesDir ~= nil and metadata.kind ~= "dir" then
    log.err(
        "--prune with --instances-dir needs a directory target, so every declaration "
            .. "writing into it is read first"
    )
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

-- 4b. Instances no schema of this run accounts for.
--
-- After the loop, never inside it: with a shared directory, a per-schema pass
-- sees every other schema's instances as orphans and deletes them. What makes a
-- file an orphan is that NO declaration names it.
--
-- Skipped entirely when one declaration was read into a directory it may share,
-- because then the run knows nothing about the rest of the directory and every
-- name in it would be reported as an orphan it is not.
local accountedFor = metadata.kind == "dir" or instancesDir == nil

for directory, expected in if accountedFor then claims else {} do
    if not fs.metadata(directory).exists then
        continue
    end

    for _, entry in fs.readDir(directory) do
        if expected[entry] or not string.match(entry, "%.model%.json$") then
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
