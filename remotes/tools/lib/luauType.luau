--> Pulling the fields out of a `type X = { ... }` written in a Luau source file.
--
-- Text, not a real parser: it reads the shape of a declaration well enough to
-- generate code from it, and gives up loudly rather than guessing. Shared by
-- lune/hooks.luau and lune/remotes.luau, which both treat a type declaration as
-- the source of truth for files they write.

export type Field = { name: string, luauType: string }

local luauType = {}

-- Strip comments before anything else, so a `--[=[ doc ]=]` block or a
-- commented-out field never reaches the field splitter.
function luauType.stripComments(source: string): string
    local out = string.gsub(source, "%-%-%[=*%[.-%]=*%]", " ")
    out = string.gsub(out, "%-%-[^\n]*", "")
    return out
end

-- The body of `type <name> = { ... }`, brace-matched rather than
-- pattern-matched: nested table types are common, and a lazy `%b{}` on the raw
-- file stops at the first inner brace.
function luauType.body(source: string, name: string): string?
    -- `export type X` contains `type X`, so one pattern covers both.
    local _, typeStart = string.find(source, "type%s+" .. name .. "%s*=%s*{")
    if not typeStart then
        return nil
    end

    local depth = 1
    local index = typeStart + 1

    while index <= #source do
        local char = string.sub(source, index, index)
        if char == "{" then
            depth += 1
        elseif char == "}" then
            depth -= 1
            if depth == 0 then
                return string.sub(source, typeStart + 1, index - 1)
            end
        end
        index += 1
    end

    return nil
end

-- Split a type body on its top-level separators. Depth is tracked for {} () []
-- and <>, with one exception: a `>` right after a `-` is the tail of `->` in a
-- function type, not the end of a generic.
function luauType.split(body: string): { string }
    local entries: { string } = {}
    local depth = 0
    local start = 1

    for index = 1, #body do
        local char = string.sub(body, index, index)

        if char == "{" or char == "(" or char == "[" or char == "<" then
            depth += 1
        elseif char == "}" or char == ")" or char == "]" then
            depth -= 1
        elseif char == ">" then
            if string.sub(body, index - 1, index - 1) ~= "-" then
                depth -= 1
            end
        elseif (char == "," or char == ";") and depth == 0 then
            table.insert(entries, string.sub(body, start, index - 1))
            start = index + 1
        end
    end

    table.insert(entries, string.sub(body, start))

    return entries
end

-- The named fields of `type <name>` in `source`, in declaration order.
-- Indexers such as `[any]: never` have no field name and are skipped.
function luauType.fields(source: string, name: string): { Field }
    local body = luauType.body(luauType.stripComments(source), name)
    if not body then
        return {}
    end

    local fields: { Field } = {}

    for _, entry in luauType.split(body) do
        local fieldName, fieldType = string.match(entry, "^%s*([%a_][%w_]*)%s*:%s*(.-)%s*$")
        if fieldName and fieldType ~= "" then
            table.insert(fields, { name = fieldName, luauType = fieldType })
        end
    end

    return fields
end

return luauType
