# remotes

Type shims for Roblox remotes that keep untrusted input untrusted, and a
generator that writes the instance files and the lookup barrel from a single
declaration.

## The idea

A remote is the one place in a Roblox codebase where data arrives from a
machine you do not control. Every typed-remote helper has to decide what to
tell the compiler about that data, and most of them get it backwards.

Given `RemoteEvent<string, number>`, the obvious signature for the server
handler is `(player: Player, string, number)`. It is also a lie. The client
picks what it sends, including how many arguments. Writing that signature does
not make the payload a string and a number; it makes the compiler agree that it
already is one, so `payload.itemId` typechecks and nothing stops you.

So the server-facing side is typed `...unknown`. That is not a weaker type than
`T...`, it is the accurate one, and it forces the runtime check that had to
happen anyway. Sending stays fully typed in both directions, because what you
send is yours and a mistake there is your bug, not an attack.

The same asymmetry appears inside a single line of `RemoteFunction`: the
arguments are `...unknown`, the return stays `R...`, because the return is the
promise you made the client and the compiler should hold you to it.

The second idea is smaller and pays off just as often. Remote types are named
for their destination, so `ToClient` has no `FireServer` and no
`OnServerEvent`, and `ToServer` has neither `FireClient` nor `OnClientEvent`.
Using one the wrong way round stops compiling instead of silently connecting to
something that will never fire. That mistake is invisible otherwise: the remote
exists, the call typechecks, and nothing happens.

## What this is not

Blink, Zap and ByteNet solve a different problem. They own the wire: a schema
in their own DSL, a code generator, binary serialization, and runtime
validation derived from the schema. If you want a compact wire format and
validation you do not have to write, use one of those. They are good.

This entry makes the opposite bet. There is no runtime, no DSL and no
serialization. `RemoteTypes.luau` returns an empty table; every export is a
type, and a "typed remote" here is a cast that vanishes at compile time. What
you get is documentation the compiler enforces at the call site and hover text
in your editor. What you do not get is validation: `...unknown` tells you the
check is missing, it does not perform it.

That trade is worth it when you want your declarations to be ordinary Luau that
typechecks, autocompletes and carries doc comments without a second toolchain
in the build. It is not worth it when the wire format is your bottleneck.

## Files

| File | Where it goes |
|---|---|
| `game/RemoteTypes.luau` | Into the place, next to your other shared libraries |
| `tools/generate.luau` | Stays on your machine, run with Lune |
| `tools/lib/*` | Stays on your machine, required by the generator |
| `examples/*` | Stays in this repo, analyzed by `just check` |

## Using the types

Copy `game/RemoteTypes.luau` into your shared library folder. Declare your
remotes in ordinary Luau, one type per feature:

```lua
export type Remotes = {
    --[=[
        Asks the server to buy an item; the server decides whether it can be
        afforded, the client is only expressing intent.
    ]=]
    BuyItem: RemoteTypes.ToServer<string, number>,
    BadgeAwarded: RemoteTypes.ToClient<number>,
}
```

Then read `examples/RemoteExample.luau`, which is the part that matters. It
shows how to get from `unknown` back to a real type: `typeof` guards for
scalars, and for tables a validator with the honest signature
`(unknown) -> T?` that rebuilds the value rather than casting it, so what comes
out has exactly the promised fields and nothing the client smuggled in.

## Using the generator

```sh
lune run tools/generate.luau -- path/to/ShopRemotesSchema.luau
lune run tools/generate.luau -- Shop --features-root modules --instances Net
lune run tools/generate.luau -- features --instances-dir shared/Remotes --instances-path ReplicatedStorage.Remotes
```

| Option | Default | What it is |
|---|---|---|
| `--instances <name>` | `Remotes` | Folder for the generated instance files, next to the declaration |
| `--instances-dir <path>` | next to the declaration | Where the instance files go, when that is not next to the declaration. Overrides `--instances` |
| `--instances-path <expr>` | `script.Parent.<instances>` | How the barrel reaches them in the datamodel. A leading service name is resolved with `GetService` |
| `--features-root <dir>` | `features` | Where a bare `FeatureName` argument is looked up |
| `--schema-suffix <s>` | `RemotesSchema.luau` | Filename suffix that marks a declaration when scanning a directory. Must end in `Schema.luau` unless `--barrel` is given |
| `--barrel <name>` | derived | Name the generated module outright. One declaration at a time |
| `--prune` | off | Delete instance files no declaration of the run names |
| `--dry` | off | Print what would happen, write nothing |

One thing is fixed rather than configurable: the `export type Remotes` name,
which is what makes a declaration readable at all.

The generated module's name is derived by default: the declaration's name with
the trailing `Schema` dropped, so `CombatNetSchema.luau` produces
`CombatNet.luau`. The two files then sit side by side with names that answer
each other, rather than through a mapping kept somewhere else. `--barrel` names
it outright when that is not what you want, and takes one declaration at a time
— pointed at a directory, every barrel would be written over the same file.

`--schema-suffix` must end in `Schema.luau`, and that is checked. Finding a
declaration and naming its barrel are two rules that have to agree, and an
unchecked suffix lets them drift: a file the directory scan skips still
generates fine when pointed at directly, which is a confusing way to discover a
typo. With `--barrel`, nothing is derived and the rule has nothing left to
protect, so it is not enforced.

## Putting the remotes somewhere shared

Where things live is two questions, not one. `--instances-dir` is a path on
disk; `--instances-path` is a path in the datamodel. Rojo decides how the first
maps to the second, and it can map them any way it likes, so neither can be
derived from the other — which is why one option cannot do both, and why
`--instances-dir` on its own warns rather than guessing.

```sh
lune run tools/generate.luau -- features     --instances-dir src/shared/Remotes     --instances-path ReplicatedStorage.Remotes
```

Every declaration under `features/` then writes its instances into one folder,
and each barrel opens with the service it needs:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes: ShopRemotesSchema.Remotes = {
    BuyItem = ReplicatedStorage.Remotes.BuyItem :: any,
}
```

Remote names become global once the folder is, so two features cannot both
declare `Ping`. Nothing detects the collision: the second declaration simply
generates the same file.

`--prune` deletes what **no** declaration of the run names, which is why it
reads every schema before deleting anything. Pruning one declaration into a
shared folder would delete the others' instances, so with `--instances-dir` it
requires a directory target and refuses a single file. For the same reason, a
single declaration read into a shared folder reports no orphans at all: that run
does not know what the rest of the folder is for.

From a declaration it writes, and overwrites whole, one `.model.json` per
remote with the class the payload type implies, plus the barrel module your
code requires. The declaration is the only file you edit; everything
downstream is generated and never touched by hand.

The barrel deliberately names no payload type. It annotates its table with
`Remotes` and casts each instance to `any`. The annotation is what makes a
remote missing from the barrel a compile error, and the cast is what gets past
the invariance of table properties, since the sourcemap types the instance as
`RemoteEvent` and that is not the same type as `Instance & {...}`. The result
is that each payload type is written exactly once.
